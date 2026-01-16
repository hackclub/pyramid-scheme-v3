# frozen_string_literal: true

module Api
  module V1
    class CodesController < BaseController
      # GET /api/v1/codes
      # Returns all valid referral codes for the campaign
      def index
        codes = []

        # User referral codes (users are global, but we filter to those with activity in this campaign)
        # Actually, all user codes are valid for any campaign
        User.where.not(referral_code: nil).find_each do |user|
          codes << { code: user.referral_code, type: "user" }
          # Also include custom referral code if set
          if user.custom_referral_code.present?
            codes << { code: user.custom_referral_code, type: "user", custom: true }
          end
        end

        # Poster referral codes for this campaign
        poster_codes = current_campaign.posters
          .where(verification_status: "success")
          .where.not(referral_code: nil)
          .pluck(:referral_code)
        codes.concat(poster_codes.map { |code| { code: code, type: "poster" } })

        render_success(
          campaign: current_campaign.slug,
          codes: codes,
          total: codes.size
        )
      end

      # GET /api/v1/codes/:code
      # Check if a specific referral code is valid for the campaign
      def show
        code = params[:id].to_s.strip

        # Try to find user by any referral code (standard or custom)
        user = User.find_by_any_referral_code(code)
        if user
          return render_success(
            code: code,
            valid: true,
            type: "user",
            user: {
              display_name: user.display_name,
              referral_count: user.referral_count
            }
          )
        end

        code_upper = code.upcase

        # Check if it's a valid format for poster code (8 alphanumeric)
        unless code_upper.match?(/^[A-Z0-9]{8}$/)
          return render_success(
            code: params[:id],
            valid: false,
            reason: "invalid_format"
          )
        end

        # Check poster codes for this campaign
        poster = current_campaign.posters
          .where(verification_status: "success")
          .find_by(referral_code: code_upper)

        if poster
          return render_success(
            code: code_upper,
            valid: true,
            type: "poster",
            poster: {
              location: poster.location_description,
              verified_at: poster.verified_at
            }
          )
        end

        # Check if poster exists but isn't verified yet
        pending_poster = current_campaign.posters.find_by(referral_code: code_upper)
        if pending_poster
          return render_success(
            code: code_upper,
            valid: false,
            reason: "poster_not_verified",
            status: pending_poster.verification_status
          )
        end

        render_success(
          code: code_upper,
          valid: false,
          reason: "not_found"
        )
      end
    end
  end
end
