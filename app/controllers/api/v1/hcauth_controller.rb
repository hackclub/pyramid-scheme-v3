# frozen_string_literal: true

module Api
  module V1
    class HcauthController < BaseController
      def addresses
        access_token = session[:hc_auth_token]

        if access_token.blank?
          return render json: { error: "Not authenticated", addresses: [] }, status: :unauthorized
        end

        addresses = HackClubAuthService.fetch_addresses(access_token)
        render json: { addresses: addresses }
      rescue HackClubAuthService::AuthenticationError => e
        Rails.logger.error("HCAuth address fetch failed: #{e.message}")
        render json: { error: e.message, addresses: [] }, status: :unauthorized
      rescue StandardError => e
        Rails.logger.error("Unexpected error fetching addresses: #{e.message}")
        render json: { error: "Failed to fetch addresses", addresses: [] }, status: :internal_server_error
      end
    end
  end
end
