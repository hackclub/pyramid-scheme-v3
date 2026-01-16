# frozen_string_literal: true

class HcauthController < ApplicationController
  def addresses
    access_token = session[:hc_auth_token]

    if access_token.blank?
      return render json: {
        addresses: [],
        reauth_url: auth_path
      }, status: :unauthorized
    end

    addresses = HackClubAuthService.fetch_addresses(access_token)

    render json: { addresses: addresses }
  rescue HackClubAuthService::AuthenticationError => e
    Rails.logger.error("HCAuth address fetch failed: #{e.message}")
    render json: { addresses: [], reauth_url: auth_path }, status: :unauthorized
  rescue StandardError => e
    Rails.logger.error("Unexpected error fetching HCAuth addresses: #{e.class}: #{e.message}")
    render json: { addresses: [] }, status: :internal_server_error
  end
end
