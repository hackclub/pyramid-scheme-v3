# frozen_string_literal: true

# Stores referral data synced from Airtable
class AirtableReferral < ApplicationRecord
  belongs_to :campaign, optional: true, inverse_of: :airtable_referrals

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :referral_code, presence: true
  validates :airtable_record_id, presence: true, uniqueness: true
  validates :source_table, presence: true

  scope :from_users, -> { where(source_table: "_users") }
  scope :recently_synced, -> { where("synced_at > ?", 5.minutes.ago) }
  scope :for_campaign, ->(campaign) { where(campaign: campaign) }
  scope :recent, -> { order(synced_at: :desc) }
  scope :with_campaign, -> { includes(:campaign) }
  scope :by_referral_code, ->(code) { where(referral_code: code.to_s.strip.upcase) }

  # Check if referral code is valid (exists in posters table)
  def self.valid_referral_code?(code)
    normalized_code = code.to_s.strip.upcase
    return false if normalized_code.blank?

    User.exists?(referral_code: normalized_code) || Poster.exists?(referral_code: normalized_code)
  end

  # Find or create from Airtable record
  def self.sync_from_airtable(record:, source_table:, campaign: nil, field_mappings: {})
    fields = record["fields"] || {}

    # Use field mappings to extract data
    email_field = field_mappings["email"] || "Email"
    ref_field = field_mappings["referral_code"] || "Referral Code"
    name_field = field_mappings["name"] || "Name"
    slack_id_field = field_mappings["slack_id"] || "Slack ID"
    hours_field = field_mappings["hours"] || "Hours"
    idv_field = field_mappings["idv_status"] || "IDV Status"
    projects_field = field_mappings["projects_shipped"] || "Projects Shipped"
    projects_count_field = field_mappings["projects_count"] || "Project Count"
    ships_count_field = field_mappings["ships_count"] || "Verified Shipped Count"

    referral_code = (fields[ref_field] || fields["Referral Code"]).to_s.strip.upcase
    email = (fields[email_field] || fields["Email"] || fields["email"]).to_s.strip.downcase
    name = fields[name_field] || fields["Name"] || fields["name"]
    slack_id = fields[slack_id_field] || fields["Slack ID"] || fields["slack_id"]
    hours = fields[hours_field] || fields["Hours"] || fields["hours"]
    idv_status = fields[idv_field] || fields["IDV Status"] || fields["verification_status"]
    projects_shipped = fields[projects_field] || fields["Projects Shipped"] || fields["projects_shipped"]
    projects_count = fields[projects_count_field] || fields["Project Count"]
    ships_count = fields[ships_count_field] || fields["Verified Shipped Count"]
    record_id = record["id"]
    context = "record #{record_id} (source: #{source_table}, ref: #{referral_code}, email: #{email.presence || '[none]'})"

    if email.blank?
      Rails.logger.warn "Skipping Airtable referral #{context} because email is missing"
      return nil
    end

    # Skip if referral code is invalid
    unless valid_referral_code?(referral_code)
      Rails.logger.warn "Skipping Airtable referral #{context} due to unknown referral code"
      return nil
    end

    find_or_initialize_by(airtable_record_id: record_id).tap do |referral|
      referral.campaign = campaign
      referral.email = email
      referral.name = name.presence || "No name provided"
      referral.slack_id = slack_id
      referral.referral_code = referral_code
      referral.source_table = source_table
      referral.synced_at = Time.current
      referral.metadata = {
        raw_fields: fields,
        hours: hours,
        idv_status: idv_status,
        projects_shipped: projects_shipped,
        projects_count: projects_count,
        ships_count: ships_count
      }
      referral.save!
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Failed to sync Airtable referral #{context} - validation failed: #{e.record.errors.full_messages.join(', ')}"
    nil
  rescue StandardError => e
    Rails.logger.error "Failed to sync Airtable referral #{context} - #{e.class}: #{e.message}"
    nil
  end

  # Extract hours from metadata
  def hours
    metadata&.dig("hours")
  end

  # Extract IDV status from metadata
  def idv_status
    metadata&.dig("idv_status")
  end

  # Extract projects shipped from metadata
  def projects_shipped
    metadata&.dig("projects_shipped")
  end

  # Extract ships count from metadata (for Construct)
  def ships_count
    metadata&.dig("ships_count")
  end

  # Extract projects count from metadata (for Construct)
  def projects_count
    metadata&.dig("projects_count")
  end
end
