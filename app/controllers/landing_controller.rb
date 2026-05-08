# frozen_string_literal: true

class LandingController < ApplicationController
  skip_before_action :authenticate_user!
  layout "landing"

  def index
    @campaign = landing_campaign
    return render_sunset if @campaign.blank?

    # Capture referral code from URL parameter
    if params[:ref].present?
      session[:referral_code] = params[:ref].strip
      Rails.logger.info("Captured referral code: #{session[:referral_code]}")
    end
  end

  private

  def render_sunset
    clear_campaign_flash
    render :sunset, layout: "application"
  end

  def clear_campaign_flash
    campaign_alerts = [
      t("campaigns.errors.closed"),
      t("campaigns.errors.coming_soon"),
      t("campaigns.errors.not_found")
    ]

    flash.delete(:alert) if campaign_alerts.include?(flash[:alert])
  end

  def landing_campaign
    flavortown = Campaign.flavortown
    return flavortown if flavortown&.open?

    Campaign.current.open_status.first
  end
end
