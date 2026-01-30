# frozen_string_literal: true

# Imports referral data from Airtable into the local database.
#
# This service handles syncing user referral records from an Airtable base,
# supporting both full imports and incremental updates. It maps Airtable
# field names to local model attributes using campaign-specific field mappings.
#
# @example Import all referrals for a campaign
#   importer = AirtableReferralImporter.new(campaign: campaign)
#   stats = importer.import_all
#   # => { total: 100, created: 50, updated: 30, skipped: 20, errors: [] }
#
# @example Import only new records since last sync
#   importer = AirtableReferralImporter.new(campaign: campaign)
#   stats = importer.import_new
class AirtableReferralImporter
  class ImportError < StandardError; end

  attr_reader :client, :table_name, :campaign

  # Initializes a new importer for the given campaign.
  #
  # @param campaign [Campaign] The campaign to import referrals for
  # @param table_name [String, nil] Optional override for the Airtable table name
  def initialize(campaign:, table_name: nil)
    # Use campaign-specific Airtable base if configured, otherwise fall back to global
    base_id = campaign&.airtable_base_id.presence || ENV["AIRTABLE_BASE_ID"]
    @client = AirtableClient.new(base_id: base_id)
    @table_name = table_name || campaign&.airtable_table_id.presence || ENV["AIRTABLE_USERS_TABLE_NAME"] || "_users"
    @campaign = campaign
  end

  # Import all referrals from Airtable _users table
  # @return [Hash] Import statistics
  def import_all
    # Import all users who have a ref code (any hours, any status)
    ref_field = referral_code_field_name
    formula = "{#{ref_field}} != ''"
    records = client.fetch_all(table_name, formula: formula)
    import_records(records)
  end

  # Import only new/modified referrals since the last import
  # @return [Hash] Import statistics
  def import_new
    last_import = AirtableImport.for_table(table_name).recently_imported.first
    since = last_import&.last_imported_at || 1.year.ago

    # Import all users with ref codes that were modified since last import
    ref_field = referral_code_field_name
    formula = "AND({#{ref_field}} != '', IS_AFTER(LAST_MODIFIED_TIME(), '#{since.iso8601}'))"
    records = client.fetch_all(table_name, formula: formula)
    import_records(records)
  end

  # Import a specific record by Airtable ID
  # @param airtable_record_id [String] The Airtable record ID
  # @return [Referral] The imported referral
  def import_record(airtable_record_id)
    record = client.fetch_record(table_name, airtable_record_id)
    process_record(record)
  end

  # Repair missing referrals from existing airtable_referrals records
  # This processes airtable_referrals that don't have corresponding Referral records
  # @return [Hash] Import statistics
  def repair_missing
    stats = {
      total: 0,
      created: 0,
      updated: 0,
      skipped: 0,
      errors: []
    }

    # Find airtable_referrals that don't have corresponding referrals
    missing = AirtableReferral
                .joins("LEFT JOIN referrals ON LOWER(referrals.referred_identifier) = LOWER(airtable_referrals.email)")
                .where(referrals: { id: nil })
                .where(campaign: campaign)

    missing.find_each do |ar|
      stats[:total] += 1
      begin
        result = process_airtable_referral(ar)
        stats[result] += 1
      rescue StandardError => e
        stats[:errors] << { email: ar.email, error: e.message }
        Rails.logger.error "Failed to repair referral for #{ar.email}: #{e.message}"
      end
    end

    Rails.logger.info "[AirtableImporter] Repair completed: #{stats.inspect}"
    stats
  end

  private

  # Process an AirtableReferral record to create/update a Referral
  def process_airtable_referral(ar)
    fields = ar.metadata&.dig("raw_fields") || {}
    referrer_code = ar.referral_code
    referred_email = ar.email

    # Check if this is a poster referral
    poster = Poster.find_by(referral_code: referrer_code)
    is_poster_referral = poster.present?

    if is_poster_referral
      referrer = poster.user
    else
      referrer = User.find_by_any_referral_code(referrer_code)
    end

    unless referrer
      Rails.logger.warn "Referrer not found for code: #{referrer_code}, skipping"
      return :skipped
    end

    # Find the referred user by email
    referred = User.find_by(email: referred_email)

    # Get hours and verification status from metadata
    hours = ar.hours.to_f
    verification_status = ar.idv_status

    status = case verification_status&.downcase
    when "verified", "verified_eligible"
      :id_verified
    else
      :pending
    end

    # Find or create the referral
    referral = Referral.find_or_initialize_by(
      referrer: referrer,
      referred_identifier: referred_email,
      campaign: campaign
    )

    return :skipped if referral.persisted? && referral.completed?

    referral.assign_attributes(
      referred: referred,
      tracked_minutes: (hours * 60).to_i,
      external_program: campaign&.name,
      referral_type: is_poster_referral ? "poster" : "link"
    )
    referral.status = status unless referral.completed?

    is_new = referral.new_record?
    referral.save!

    if referral.id_verified? && referral.tracked_minutes >= campaign.required_coding_minutes
      referral.complete!
    end

    is_new ? :created : :updated
  end

  def import_records(records)
    stats = {
      total: records.count,
      created: 0,
      updated: 0,
      skipped: 0,
      errors: []
    }

    records.each do |record|
      begin
        result = process_record(record)
        stats[result] += 1
      rescue StandardError => e
        stats[:errors] << { record_id: record[:id], error: e.message }
        Rails.logger.error "Failed to import record #{record[:id]}: #{e.message}"
      end
    end

    stats
  end

  def process_record(record)
    airtable_record_id = record[:id]
    fields = record[:fields]

    # Check if we've already imported this record
    existing_import = AirtableImport.find_by(
      table_name: table_name,
      airtable_record_id: airtable_record_id
    )

    # Get campaign-specific field mappings
    field_mappings = campaign&.effective_field_mappings || Campaign::DEFAULT_FIELD_MAPPINGS
    ref_field = field_mappings["referral_code"] || "Referral Code"
    email_field = field_mappings["email"] || "Email"
    hours_field = field_mappings["hours"] || "Hours"
    idv_field = field_mappings["idv_status"] || "IDV Status"
    ships_field = field_mappings["ships_count"] || "Verified Ship Count"
    projects_field = field_mappings["projects_count"] || "Project Count"

    # Extract data from Airtable using field mappings (with fallbacks)
    referrer_code = (fields[ref_field] || fields["Referral Code"])&.strip&.upcase
    referred_email = (fields[email_field] || fields["email"] || fields["Email"])&.strip&.downcase
    hours = (fields[hours_field] || fields["hours"] || fields["Hours"] || 0).to_f
    verification_status = fields[idv_field] || fields["verification_status"] || fields["IDV Status"]
    ships_count = (fields[ships_field] || fields["Ships"] || fields["Verified Ship Count"] || 0).to_i
    projects_count = (fields[projects_field] || fields["Projects"] || fields["Project Count"] || 0).to_i

    # Skip if no referrer code or email
    unless referrer_code.present? && referred_email.present?
      Rails.logger.warn "Missing referral code or email in record #{airtable_record_id}, skipping"
      return :skipped
    end

    # Find the referrer by their referral code or custom referral code
    # First check if it's a poster code, then check for user codes
    poster = Poster.find_by(referral_code: referrer_code)
    is_poster_referral = poster.present?

    if is_poster_referral
      referrer = poster.user
    else
      referrer = User.find_by_any_referral_code(referrer_code)
    end

    unless referrer
      Rails.logger.warn "Referrer not found for code: #{referrer_code}, skipping record #{airtable_record_id}"
      return :skipped
    end

    # Find the referred user by email (optional, may not exist in our system)
    referred = User.find_by(email: referred_email)

    # Map verification status to our referral status
    # Note: We set to id_verified when verified, then call complete! to check time requirement
    status = case verification_status&.downcase
    when "verified", "verified_eligible"
      :id_verified  # User has been verified (but may not have met time requirement yet)
    when "needs_submission"
      :pending  # User needs to submit verification
    else
      :pending
    end

    # Find or create the referral
    referral = Referral.find_or_initialize_by(
      referrer: referrer,
      referred_identifier: referred_email,
      campaign: campaign
    )

    # IMPORTANT: Never modify completed referrals - they've already been paid out
    if referral.persisted? && referral.completed?
      Rails.logger.info "Skipping completed referral #{referral.id} for #{referred_email} - already completed"
      return :skipped
    end

    # Update referral attributes
    # Don't change status if referral is already completed (prevents re-awarding shards)
    attributes_to_update = {
      referred: referred,
      tracked_minutes: (hours * 60).to_i,  # Convert hours to minutes
      external_program: campaign&.name,  # Set to campaign name
      referral_type: is_poster_referral ? "poster" : "link"  # Set based on referrer code type
    }

    # Only update status if referral is not completed (prevents downgrading completed -> id_verified)
    attributes_to_update[:status] = status unless referral.completed?

    referral.assign_attributes(attributes_to_update)

    # Store metadata including censored email and verification status
    referral.metadata ||= {}
    referral.metadata["airtable_data"] = fields
    referral.metadata["airtable_record_id"] = airtable_record_id
    referral.metadata["last_imported_at"] = Time.current.iso8601
    referral.metadata["hours"] = hours
    referral.metadata["verification_status"] = verification_status
    referral.metadata["censored_email"] = censor_email(referred_email)
    referral.metadata["ships_count"] = ships_count
    referral.metadata["projects_count"] = projects_count

    # Determine if this is a create or update
    is_new = referral.new_record?

    # Save the referral
    referral.save!

    # Try to complete the referral based on campaign type
    # For ships-based campaigns (like Construct), check ships_count >= 1
    # For hours-based campaigns, check id_verified && tracked_minutes >= required
    should_complete = if ships_based_campaign?
      # Ships-based: everyone is ID verified, just need ships >= 1
      ships_count >= 1
    else
      # Hours-based: need ID verification and enough coding time
      referral.id_verified? && referral.tracked_minutes >= campaign.required_coding_minutes
    end

    if should_complete && !referral.completed?
      # For ships-based campaigns, mark as id_verified first if not already
      referral.update!(status: :id_verified) if ships_based_campaign? && referral.pending?
      referral.complete!
    end

    # Create or update the import record
    import_record = AirtableImport.find_or_initialize_for(
      table_name,
      airtable_record_id,
      referral
    )
    import_record.raw_data = fields
    import_record.mark_imported!

    is_new ? :created : :updated
  end

  # Censors an email address by masking the local part.
  # Shows first and last character of local part, rest as asterisks.
  #
  # @param email [String] The email address to censor
  # @return [String] The censored email address
  # @example
  #   censor_email("john.doe@example.com") # => "j******e@example.com"
  #
  # @note This duplicates ApplicationHelper#censor_email - consider extracting
  #   to a shared module if more services need this functionality.
  def censor_email(email)
    return email if email.blank? || email.length <= 2

    local, domain = email.split("@")
    return email if local.blank? || domain.blank?

    censored_local = if local.length <= 2
      local
    else
      "#{local[0]}#{'*' * (local.length - 2)}#{local[-1]}"
    end

    "#{censored_local}@#{domain}"
  end

  # Get the referral code field name from campaign mappings
  def referral_code_field_name
    field_mappings = campaign&.effective_field_mappings || Campaign::DEFAULT_FIELD_MAPPINGS
    field_mappings["referral_code"] || "Referral Code"
  end

  # Check if this is a ships-based campaign (like Construct)
  # Ships-based campaigns track project ships instead of coding hours
  def ships_based_campaign?
    campaign&.slug == "construct"
  end
end
