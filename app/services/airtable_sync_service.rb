# frozen_string_literal: true

# Service to sync referral data from Airtable to PostgreSQL
# Now supports per-campaign configuration
class AirtableSyncService
  # Required ENV vars - no fallbacks for security
  GLOBAL_BASE_ID = ENV.fetch("AIRTABLE_BASE_ID")
  GLOBAL_USERS_TABLE_ID = ENV.fetch("AIRTABLE_USERS_TABLE_ID")
  PERSONAL_ACCESS_TOKEN = ENV.fetch("AIRTABLE_PAT", nil)

  attr_reader :stats, :campaign

  def initialize(campaign: nil)
    @campaign = campaign
    @stats = {
      users_synced: 0,
      users_skipped: 0,
      errors: []
    }
  end

  def perform
    log "Starting Airtable sync#{campaign ? " for campaign: #{campaign.name}" : " (global)"}..."
    start_time = Time.current

    base_id = campaign&.airtable_base_id.presence || GLOBAL_BASE_ID
    table_id = campaign&.airtable_table_id.presence || GLOBAL_USERS_TABLE_ID
    field_mappings = campaign&.effective_field_mappings || Campaign::DEFAULT_FIELD_MAPPINGS

    # Sync users table
    sync_table(
      base_id: base_id,
      table_id: table_id,
      table_name: "_users",
      field_mappings: field_mappings
    )

    duration = Time.current - start_time
    log "Airtable sync completed in #{duration.round(2)}s: #{@stats.inspect}"

    @stats
  rescue => e
    log "Airtable sync failed: #{e.message}", level: :error
    log e.backtrace.join("\n"), level: :error
    @stats[:errors] << e.message
    @stats
  end

  # Sync all campaigns with Airtable enabled
  def self.sync_all_campaigns
    results = {}

    # Sync campaigns with their own Airtable config
    Campaign.with_airtable_sync.find_each do |campaign|
      service = new(campaign: campaign)
      results[campaign.slug] = service.perform
    end

    results
  end

  private

  def sync_table(base_id:, table_id:, table_name:, field_mappings:)
    return unless table_id.present? && base_id.present?

    log "Syncing #{table_name} table from base #{base_id}..."
    records = fetch_records(base_id, table_id)

    # Get field names from mappings
    email_field = field_mappings["email"] || "Email"
    ref_field = field_mappings["referral_code"] || "ref"

    records.each do |record|
      fields = record["fields"] || {}
      ref_code = (fields[ref_field] || fields["ref"]).to_s.strip
      email = fields[email_field].presence || fields["Email"].presence || fields["email"].presence
      record_id = record["id"]

      # Skip records without ref field
      unless ref_code.present?
        log "Skipping #{table_name} record #{record_id} because ref code is missing (email: #{email.presence || '[none]'})", level: :warn
        @stats[:"#{table_name[1..]}_skipped"] += 1
        next
      end

      # Skip records without email
      unless email.present?
        log "Skipping #{table_name} record #{record_id} because email is missing (ref: #{ref_code})", level: :warn
        @stats[:"#{table_name[1..]}_skipped"] += 1
        next
      end

      normalized_record = record.deep_dup
      normalized_record["fields"] ||= {}
      normalized_record["fields"]["Email"] ||= email
      normalized_record["fields"]["email"] ||= email
      normalized_record["fields"]["ref"] ||= ref_code

      result = AirtableReferral.sync_from_airtable(
        record: normalized_record,
        source_table: table_name,
        campaign: campaign,
        field_mappings: field_mappings
      )
      if result
        @stats[:"#{table_name[1..]}_synced"] += 1
      else
        log "Airtable referral not persisted for record #{record_id} (table: #{table_name}, ref: #{ref_code}, email: #{email})", level: :warn
        @stats[:"#{table_name[1..]}_skipped"] += 1
      end
    end

    log "Finished syncing #{table_name}: #{@stats[:"#{table_name[1..]}_synced"]} synced, #{@stats[:"#{table_name[1..]}_skipped"]} skipped"
  end

  def fetch_records(base_id, table_id)
    all_records = []
    offset = nil

    loop do
      url = "https://api.airtable.com/v0/#{base_id}/#{table_id}"
      url += "?offset=#{offset}" if offset

      response = Faraday.get(url) do |req|
        req.headers["Authorization"] = "Bearer #{PERSONAL_ACCESS_TOKEN}"
        req.headers["Content-Type"] = "application/json"
      end

      unless response.success?
        raise "Airtable API request failed: #{response.status} - #{response.body}"
      end

      data = JSON.parse(response.body)
      all_records.concat(data["records"] || [])

      offset = data["offset"]
      break unless offset
    end

    all_records
  end

  def log(message, level: :info)
    case level
    when :error
      Rails.logger.error "[AirtableSync] #{message}"
    when :warn
      Rails.logger.warn "[AirtableSync] #{message}"
    else
      Rails.logger.info "[AirtableSync] #{message}"
    end
  end
end
