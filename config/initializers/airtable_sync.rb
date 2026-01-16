# frozen_string_literal: true

# Ensure Airtable sync runs immediately on boot (in addition to the recurring task schedule).
Rails.application.config.after_initialize do
  should_enqueue = !Rails.env.test? &&
    ENV.fetch("RUN_AIRTABLE_SYNC_ON_BOOT", "true") != "false" &&
    !defined?(Rails::Console) &&
    File.basename($PROGRAM_NAME) != "rake" &&
    File.basename($PROGRAM_NAME) != "jobs" # Don't enqueue from worker process itself

  if should_enqueue
    begin
      AirtableSyncJob.perform_later
      Rails.logger.info "[AirtableSync] Enqueued initial AirtableSyncJob on boot"
    rescue => e
      Rails.logger.error "[AirtableSync] Failed to enqueue initial AirtableSyncJob on boot: #{e.class} - #{e.message}"
    end
  end
end
