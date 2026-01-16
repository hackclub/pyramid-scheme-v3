# frozen_string_literal: true

class HealthController < ApplicationController
  # Skip all filters and authentication for health checks
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!
  skip_before_action :enforce_ban
  skip_before_action :track_user_activity

  def show
    # Check database connectivity
    ActiveRecord::Base.connection.execute("SELECT 1")

    # All checks passed - migrations check removed for Coolify compatibility
    # Coolify health checks run before entrypoint completes db:prepare,
    # so we only verify database connectivity here.
    # Migrations are verified at boot time by Rails anyway.
    render plain: "OK", status: :ok
  rescue => e
    # Database connection failed or other error
    render plain: "Error: #{e.message}", status: :service_unavailable
  end
end
