# frozen_string_literal: true

namespace :airtable do
  desc "Import referrals from Airtable for a specific campaign"
  task :import_referrals, [ :campaign_slug ] => :environment do |_t, args|
    unless args[:campaign_slug]
      puts "Usage: rails airtable:import_referrals[CAMPAIGN_SLUG]"
      puts "Example: rails airtable:import_referrals[flavortown]"
      exit 1
    end

    campaign = Campaign.find_by(slug: args[:campaign_slug])
    unless campaign
      puts "Campaign not found: #{args[:campaign_slug]}"
      exit 1
    end

    puts "Importing referrals for campaign: #{campaign.name}"
    puts "Table: #{ENV['AIRTABLE_REFERRALS_TABLE_NAME'] || 'Referrals'}"
    puts ""

    # Run the import job synchronously
    stats = AirtableReferralImportJob.new.perform(campaign.id, import_all: false)

    puts ""
    puts "Import complete!"
    puts "Total records processed: #{stats[:total]}"
    puts "Created: #{stats[:created]}"
    puts "Updated: #{stats[:updated]}"
    puts "Skipped: #{stats[:skipped]}"
    puts "Errors: #{stats[:errors].count}"

    if stats[:errors].any?
      puts ""
      puts "Errors:"
      stats[:errors].each do |error|
        puts "  Record #{error[:record_id]}: #{error[:error]}"
      end
    end
  end

  desc "Import ALL referrals from Airtable (full sync)"
  task :import_all_referrals, [ :campaign_slug ] => :environment do |_t, args|
    unless args[:campaign_slug]
      puts "Usage: rails airtable:import_all_referrals[CAMPAIGN_SLUG]"
      puts "Example: rails airtable:import_all_referrals[flavortown]"
      exit 1
    end

    campaign = Campaign.find_by(slug: args[:campaign_slug])
    unless campaign
      puts "Campaign not found: #{args[:campaign_slug]}"
      exit 1
    end

    puts "Performing FULL import of referrals for campaign: #{campaign.name}"
    puts "Table: #{ENV['AIRTABLE_REFERRALS_TABLE_NAME'] || 'Referrals'}"
    puts "This will import all records from Airtable, not just new ones."
    puts ""

    # Run the import job synchronously
    stats = AirtableReferralImportJob.new.perform(campaign.id, import_all: true)

    puts ""
    puts "Import complete!"
    puts "Total records processed: #{stats[:total]}"
    puts "Created: #{stats[:created]}"
    puts "Updated: #{stats[:updated]}"
    puts "Skipped: #{stats[:skipped]}"
    puts "Errors: #{stats[:errors].count}"

    if stats[:errors].any?
      puts ""
      puts "Errors:"
      stats[:errors].each do |error|
        puts "  Record #{error[:record_id]}: #{error[:error]}"
      end
    end
  end

  desc "Test Airtable connection"
  task test_connection: :environment do
    puts "Testing Airtable connection..."
    puts ""
    puts "Configuration:"
    puts "  API Key: #{ENV['AIRTABLE_API_KEY'].present? ? '[SET]' : '[NOT SET]'}"
    puts "  Base ID: #{ENV['AIRTABLE_BASE_ID'].present? ? '[SET]' : '[NOT SET]'}"
    puts "  Table Name: #{ENV['AIRTABLE_REFERRALS_TABLE_NAME'] || 'Referrals'}"
    puts ""

    begin
      client = AirtableClient.new
      table_name = ENV["AIRTABLE_REFERRALS_TABLE_NAME"] || "Referrals"

      puts "Fetching records from #{table_name}..."
      records = client.fetch_all(table_name)

      puts "Success! Found #{records.count} records"
      if records.any?
        puts ""
        puts "Sample record:"
        puts "  ID: #{records.first[:id]}"
        puts "  Fields: #{records.first[:fields].keys.join(', ')}"
      end
    rescue AirtableClient::ConfigurationError => e
      puts "Configuration error: #{e.message}"
      puts ""
      puts "Please set the following environment variables:"
      puts "  AIRTABLE_API_KEY"
      puts "  AIRTABLE_BASE_ID"
      exit 1
    rescue AirtableClient::ApiError => e
      puts "API error: #{e.message}"
      exit 1
    rescue StandardError => e
      puts "Error: #{e.message}"
      puts e.backtrace.first(5).join("\n")
      exit 1
    end
  end

  desc "Show Airtable import statistics"
  task stats: :environment do
    total_imports = AirtableImport.count
    tables = AirtableImport.distinct.pluck(:table_name)

    puts "Airtable Import Statistics"
    puts "=" * 50
    puts "Total imports: #{total_imports}"
    puts "Tables: #{tables.join(', ')}"
    puts ""

    tables.each do |table_name|
      imports = AirtableImport.for_table(table_name)
      puts "#{table_name}:"
      puts "  Total: #{imports.count}"
      puts "  Last import: #{imports.recently_imported.first&.last_imported_at || 'Never'}"
      puts ""
    end
  end

  desc "Sync referrals from Airtable continuously (every 60 seconds)"
  task :sync_continuous, [ :campaign_slug ] => :environment do |_t, args|
    unless args[:campaign_slug]
      puts "Usage: rails airtable:sync_continuous[CAMPAIGN_SLUG]"
      puts "Example: rails airtable:sync_continuous[flavortown]"
      exit 1
    end

    campaign = Campaign.find_by(slug: args[:campaign_slug])
    unless campaign
      puts "Campaign not found: #{args[:campaign_slug]}"
      exit 1
    end

    puts "Starting continuous Airtable sync for campaign: #{campaign.name}"
    puts "Syncing every 60 seconds. Press Ctrl+C to stop."
    puts ""

    loop do
      begin
        start_time = Time.current
        stats = AirtableReferralImportJob.new.perform(campaign.id, import_all: false)

        puts "[#{Time.current.strftime('%H:%M:%S')}] Sync complete - Created: #{stats[:created]}, Updated: #{stats[:updated]}, Skipped: #{stats[:skipped]}, Errors: #{stats[:errors].count}"

        if stats[:errors].any?
          stats[:errors].each do |error|
            puts "  ERROR - Record #{error[:record_id]}: #{error[:error]}"
          end
        end
      rescue StandardError => e
        puts "[#{Time.current.strftime('%H:%M:%S')}] ERROR: #{e.message}"
      end

      sleep 60
    end
  end
end
