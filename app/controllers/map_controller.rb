# frozen_string_literal: true

class MapController < ApplicationController
  def index
    @country_stats = referral_stats_by_country

    respond_to do |format|
      format.html
      format.json { render json: @country_stats }
    end
  end

  private

  def referral_stats_by_country
    # Get referral counts grouped by referrer's country
    User.joins(:referrals_given)
        .where(referrals: { status: :completed })
        .where.not(country_code: nil)
        .group(:country_code)
        .count
  end
end
