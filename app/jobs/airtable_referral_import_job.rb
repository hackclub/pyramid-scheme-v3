# frozen_string_literal: true

# Job to import referrals from Airtable
# Can be run manually or scheduled to run periodically
class AirtableReferralImportJob < ApplicationJob
  queue_as :default

  # Import referrals for a specific campaign
  # @param campaign_id [Integer] The ID of the campaign to import referrals for
  # @param import_all [Boolean] If true, import all records. If false, only import new/modified records
  # @param table_name [String] Optional custom table name to import from
  def perform(campaign_id, import_all: false, table_name: nil)
    campaign = Campaign.find(campaign_id)

    importer = AirtableReferralImporter.new(
      campaign: campaign,
      table_name: table_name
    )

    stats = if import_all
      Rails.logger.info "Starting full Airtable import for campaign #{campaign.name}"
      importer.import_all
    else
      Rails.logger.info "Starting incremental Airtable import for campaign #{campaign.name}"
      importer.import_new
    end

    Rails.logger.info "Airtable import completed for campaign #{campaign.name}: #{stats.inspect}"

    # Log any errors
    if stats[:errors].any?
      Rails.logger.error "Airtable import had #{stats[:errors].count} errors:"
      stats[:errors].each do |error|
        Rails.logger.error "  Record #{error[:record_id]}: #{error[:error]}"
      end
    end

    stats
  rescue AirtableClient::ConfigurationError => e
    Rails.logger.error "Airtable configuration error: #{e.message}"
    raise
  rescue AirtableClient::ApiError => e
    Rails.logger.error "Airtable API error: #{e.message}"
    raise
  rescue StandardError => e
    Rails.logger.error "Unexpected error during Airtable import: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end
end
