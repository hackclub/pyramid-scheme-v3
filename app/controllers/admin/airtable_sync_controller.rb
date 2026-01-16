# frozen_string_literal: true

module Admin
  class AirtableSyncController < BaseController
    def run
      AirtableSyncJob.perform_later
      redirect_to admin_root_path, notice: "Airtable sync job enqueued."
    rescue => e
      redirect_to admin_root_path, alert: "Failed to enqueue Airtable sync: #{e.message}"
    end
  end
end
