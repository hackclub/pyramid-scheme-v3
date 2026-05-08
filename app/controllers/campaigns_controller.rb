# frozen_string_literal: true

class CampaignsController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :index, :show ]

  def index
    render_sunset
  end

  def show
    render_sunset
  end

  private

  def render_sunset
    clear_campaign_flash
    render "landing/sunset", layout: "application"
  end

  def clear_campaign_flash
    campaign_alerts = [
      t("campaigns.errors.closed"),
      t("campaigns.errors.coming_soon"),
      t("campaigns.errors.not_found")
    ]

    flash.delete(:alert) if campaign_alerts.include?(flash[:alert])
  end
end
