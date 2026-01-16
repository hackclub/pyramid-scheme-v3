# frozen_string_literal: true

module Admin
  class ImpersonationsController < BaseController
    # Skip admin check for destroy - we need to let impersonated non-admin users stop impersonation
    # The destroy action has its own validation to ensure we're in a valid impersonation session
    skip_before_action :require_admin!, only: [ :destroy ]
    before_action :require_impersonation_session!, only: [ :destroy ]
    before_action :require_impersonation_access!, only: [ :create ]
    before_action :set_user, only: [ :create ]

    def create
      # Store original admin user for later
      session[:impersonator_id] = current_user.id
      session[:user_id] = @user.id

      Rails.logger.info("Admin #{current_user.id} (#{current_user.slack_id}) started impersonating user #{@user.id} (#{@user.slack_id})")

      redirect_to root_path, notice: "Now impersonating #{@user.display_name}"
    end

    def destroy
      impersonator = User.find_by(id: session[:impersonator_id])
      impersonated = current_user

      if impersonator
        session[:user_id] = impersonator.id
        session.delete(:impersonator_id)

        Rails.logger.info("Admin #{impersonator.id} stopped impersonating user #{impersonated&.id}")

        redirect_to admin_user_path(impersonated), notice: "Stopped impersonating #{impersonated&.display_name}"
      else
        # Impersonator no longer exists, clear session and redirect to root
        session.delete(:impersonator_id)
        redirect_to root_path, alert: "Could not restore original session"
      end
    end

    private

    def set_user
      @user = User.find(params[:user_id])
    end

    # Ensure we're actually in an impersonation session before allowing destroy
    def require_impersonation_session!
      return if session[:impersonator_id].present?

      redirect_to root_path, alert: "Not currently impersonating anyone"
    end

    # Only allow specific admins to impersonate
    # This is an extra layer of security beyond admin?
    def require_impersonation_access!
      return if can_impersonate?

      redirect_to admin_root_path, alert: "You don't have permission to impersonate users"
    end

    def can_impersonate?
      return false unless current_user&.admin?

      # Allow the primary admin (from env) to impersonate
      admin_slack_id = ENV["ADMIN_NOTIFICATION_SLACK_ID"]
      return true if admin_slack_id.present? && current_user.slack_id == admin_slack_id

      # Also allow based on a list of allowed Slack IDs (can be extended)
      allowed_impersonators = ENV.fetch("ALLOWED_IMPERSONATORS", "").split(",").map(&:strip)
      return true if allowed_impersonators.include?(current_user.slack_id)

      false
    end
  end
end
