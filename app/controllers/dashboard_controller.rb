# frozen_string_literal: true

class DashboardController < ApplicationController
  def index
    redirect_to campaign_path(current_campaign.slug)
  end
end
