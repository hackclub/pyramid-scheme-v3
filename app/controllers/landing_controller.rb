# frozen_string_literal: true

class LandingController < ApplicationController
  skip_before_action :authenticate_user!
  layout "landing"

  def index
    @campaign = current_campaign

    # Capture referral code from URL parameter
    if params[:ref].present?
      session[:referral_code] = params[:ref].strip
      Rails.logger.info("Captured referral code: #{session[:referral_code]}")
    end
  end
end
