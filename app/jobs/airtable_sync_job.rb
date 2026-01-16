# frozen_string_literal: true

# Recurring job to sync Airtable referral data
class AirtableSyncJob < ApplicationJob
  queue_as :default

  def perform
    lock_key = 12_345_678 # arbitrary unique integer for this job
    conn = ActiveRecord::Base.connection
    acquired_lock = conn.select_value("SELECT pg_try_advisory_lock(#{lock_key})")

    unless acquired_lock
      Rails.logger.info "[AirtableSync] Skipping run; another sync is in progress"
      return
    end

    if recent_run_within?(55.seconds)
      Rails.logger.info "[AirtableSync] Skipping run; last run started < 55s ago"
      return
    end

    started_at = Time.current
    run = AirtableSyncRun.create!(status: "running", started_at: started_at)

    # Sync global Airtable (backward compatibility)
    sync_stats = AirtableSyncService.new.perform

    # Also sync per-campaign Airtable configs
    campaign_sync_stats = sync_campaign_airtables

    import_stats = perform_referral_import

    # Repair any missing referrals from existing airtable_referrals
    repair_stats = repair_missing_referrals

    # Calculate total hours from completed referrals
    hours_stats = calculate_total_hours

    message_parts = []
    if sync_stats
      synced = sync_stats[:users_synced] || sync_stats["users_synced"]
      skipped = sync_stats[:users_skipped] || sync_stats["users_skipped"]
      message_parts << "Global sync: #{synced || 0} synced, #{skipped || 0} skipped"
    end

    if campaign_sync_stats.present?
      campaign_sync_stats.each do |slug, stats|
        synced = stats[:users_synced] || stats["users_synced"] || 0
        skipped = stats[:users_skipped] || stats["users_skipped"] || 0
        message_parts << "#{slug}: #{synced} synced, #{skipped} skipped"
      end
    end

    if import_stats
      created = import_stats[:created] || import_stats["created"]
      updated = import_stats[:updated] || import_stats["updated"]
      skipped_import = import_stats[:skipped] || import_stats["skipped"]
      message_parts << "Import: #{created || 0} created, #{updated || 0} updated, #{skipped_import || 0} skipped"
    else
      message_parts << "Import skipped: no campaign found"
    end

    if repair_stats && repair_stats[:created].to_i > 0
      message_parts << "Repaired: #{repair_stats[:created]} poster referrals"
    end

    if hours_stats[:total_hours].positive?
      message_parts << "Total hours: #{hours_stats[:total_hours].round(1)}h from #{hours_stats[:completed_referrals]} completed"
    end

    run.update!(
      status: "succeeded",
      finished_at: Time.current,
      duration_seconds: Time.current - started_at,
      stats: { sync: sync_stats, campaign_syncs: campaign_sync_stats, import: import_stats, repair: repair_stats, hours: hours_stats }.compact,
      message: message_parts.join(" | ")
    )
    { sync: sync_stats, campaign_syncs: campaign_sync_stats, import: import_stats, hours: hours_stats }
  rescue => e
    run&.update!(
      status: "failed",
      finished_at: Time.current,
      duration_seconds: Time.current - started_at,
      message: "#{e.class}: #{e.message}"
    )
    raise
  ensure
    conn&.execute("SELECT pg_advisory_unlock(#{lock_key})") if acquired_lock
  end

  private

  def recent_run_within?(interval)
    last_run = AirtableSyncRun.order(started_at: :desc).limit(1).first
    last_run && last_run.started_at.present? && last_run.started_at >= Time.current - interval
  end

  def sync_campaign_airtables
    results = {}
    Campaign.with_airtable_sync.find_each do |campaign|
      Rails.logger.info "[AirtableSync] Syncing campaign: #{campaign.slug}"
      service = AirtableSyncService.new(campaign: campaign)
      results[campaign.slug] = service.perform
    end
    results
  end

  def perform_referral_import
    results = {}

    # Import for all campaigns with Airtable sync enabled (including campaign-specific bases)
    Campaign.with_airtable_sync.find_each do |campaign|
      Rails.logger.info "[AirtableSync] Importing referrals for campaign: #{campaign.slug}"
      importer = AirtableReferralImporter.new(campaign: campaign)
      # Always do incremental import for per-campaign imports
      results[campaign.slug] = importer.import_new
    end

    # Also do the global import for backward compatibility (flavortown or env-specified campaign)
    global_campaign = Campaign.find_by(slug: ENV["AIRTABLE_CAMPAIGN_SLUG"]) || Campaign.flavortown || Campaign.current.first
    if global_campaign && !global_campaign.airtable_sync_enabled?
      # Only import globally if the campaign doesn't have its own Airtable config
      importer_job = AirtableReferralImportJob.new
      any_imports = AirtableImport.for_table(default_table_name).exists?
      if any_imports
        results[:global] = importer_job.perform(global_campaign.id, import_all: false, table_name: default_table_name)
      else
        results[:global] = importer_job.perform(global_campaign.id, import_all: true, table_name: default_table_name)
      end
    end

    results
  end

  def repair_missing_referrals
    # Repair missing referrals from existing airtable_referrals records
    # This handles cases where poster referrals were synced but not imported as referrals
    all_stats = {}

    # Repair for all campaigns with Airtable sync enabled
    Campaign.with_airtable_sync.find_each do |campaign|
      Rails.logger.info "[AirtableSync] Repairing missing referrals for campaign: #{campaign.slug}"
      importer = AirtableReferralImporter.new(campaign: campaign)
      all_stats[campaign.slug] = importer.repair_missing
    end

    # Also repair for global campaign for backward compatibility
    global_campaign = Campaign.find_by(slug: ENV["AIRTABLE_CAMPAIGN_SLUG"]) || Campaign.flavortown || Campaign.current.first
    if global_campaign && !global_campaign.airtable_sync_enabled?
      importer = AirtableReferralImporter.new(campaign: global_campaign)
      all_stats[:global] = importer.repair_missing
    end

    # Return combined stats
    total_created = all_stats.values.sum { |s| s&.dig(:created).to_i }
    { created: total_created, campaigns: all_stats }
  end

  def calculate_total_hours
    # Sum hours from AirtableReferrals that correspond to completed Referrals
    # We join on email to find completed referrals and sum their hours from Airtable data
    total_hours = 0.0
    completed_count = 0

    # Get all completed referrals
    completed_referrals = Referral.completed.includes(:referred)

    completed_referrals.find_each do |referral|
      # Find matching AirtableReferral by email
      airtable_referral = AirtableReferral.find_by(email: referral.referred_identifier.downcase)
      next unless airtable_referral

      hours = airtable_referral.hours
      next unless hours.present?

      hours_value = hours.to_f
      if hours_value.positive?
        total_hours += hours_value
        completed_count += 1
      end
    end

    Rails.logger.info "[AirtableSync] Total hours from completed referrals: #{total_hours.round(1)}h from #{completed_count} users"

    {
      total_hours: total_hours,
      completed_referrals: completed_count
    }
  end

  def default_table_name
    ENV["AIRTABLE_USERS_TABLE_NAME"] || "_users"
  end
end
