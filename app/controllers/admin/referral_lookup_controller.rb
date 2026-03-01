# frozen_string_literal: true

module Admin
  class ReferralLookupController < BaseController
    def index
      @code = params[:code].to_s.strip

      if @code.present?
        perform_lookup
      end
    end

    private

    def perform_lookup
      @results = {
        current_user: nil,
        historical_owner: nil,
        poster: nil,
        referrals_using_code: [],
        airtable_referrals: [],
        code_logs: []
      }

      # Check current user codes
      user = User.find_by("LOWER(referral_code) = :code OR LOWER(custom_referral_code) = :code", code: @code.downcase)
      @results[:current_user] = user

      # Check historical codes
      history = ReferralCodeHistory.where("LOWER(code) = ?", @code.downcase).order(created_at: :desc).includes(:user)
      @results[:code_history] = history
      @results[:historical_owner] = history.first&.user if user.nil?

      # Check poster codes
      @results[:poster] = Poster.includes(:user, :campaign).find_by(referral_code: @code.upcase)

      # Find referrals where this code was used
      if user
        @results[:referrals_using_code] = Referral.where(referrer: user)
                                                   .includes(:referred, :campaign)
                                                   .order(created_at: :desc)
                                                   .limit(20)
      end

      # Check Airtable referrals using this code
      @results[:airtable_referrals] = AirtableReferral.where("LOWER(referral_code) = ?", @code.downcase)
                                                       .includes(:campaign)
                                                       .order(synced_at: :desc)
                                                       .limit(20)

      # Check referral code logs
      @results[:code_logs] = ReferralCodeLog.where("LOWER(referral_code) = ?", @code.downcase)
                                             .order(created_at: :desc)
                                             .limit(10)
    end
  end
end
