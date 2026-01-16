# frozen_string_literal: true

# Provides common patterns for admin resource handling.
# Extracts repeated error handling and record not found patterns.
module Admin
  module ResourceHandling
    extend ActiveSupport::Concern

    included do
      rescue_from ActiveRecord::RecordNotFound, with: :handle_record_not_found
    end

    private

    # Override in controller to customize the redirect path
    def resource_not_found_path
      admin_root_path
    end

    # Override in controller to customize the message
    def resource_not_found_message
      "Record not found."
    end

    def handle_record_not_found
      redirect_to resource_not_found_path, alert: resource_not_found_message
    end

    # Standard pattern for handling action errors with redirect
    # @param record [ActiveRecord::Base] Record to redirect to on error
    # @param success_path [String, Proc] Path to redirect to on success
    # @param success_message [String] Flash notice on success
    # @yield Block containing the action logic
    def with_error_handling(record:, success_path:, success_message:)
      yield
      path = success_path.respond_to?(:call) ? success_path.call : success_path
      redirect_to path, notice: success_message
    rescue ActiveRecord::RecordInvalid, ArgumentError => e
      redirect_to record, alert: e.message
    rescue StandardError => e
      Rails.logger.error("#{self.class.name} error: #{e.message}")
      redirect_to record, alert: "An error occurred: #{e.message}"
    end
  end
end
