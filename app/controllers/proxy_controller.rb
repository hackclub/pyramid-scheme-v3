# frozen_string_literal: true

# Handles proxy referral requests from flavortown.hackclub.com domain
# Routes:
# - /p/:code - Poster referral
# - /:code or /r/:code - Regular referral link
# - /avatar - Proxies Slack avatars with aggressive caching
class ProxyController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!, only: [ :poster_referral, :link_referral, :avatar ]

  # Handle poster referrals from flavortown.hackclub.com/p/:code
  def poster_referral
    code = params[:code]

    # Validate code format
    unless code.present? && code.match?(/^[A-Z0-9]{8}$/)
      redirect_to root_path, alert: "Invalid poster code format"
      return
    end

    poster = Poster.find_by(referral_code: code)

    unless poster
      redirect_to root_path, alert: "Invalid poster code"
      return
    end

    # Only log the request - don't set session variables
    poster.record_scan!(
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      country_code: request.headers["CF-IPCountry"],
      metadata: {
        referrer: request.referrer,
        referral_type: "poster_proxy"
      }
    )

    # Redirect to campaign page
    redirect_to campaign_path(poster.campaign.slug)
  end

  # Handle regular referral links from [campaign].hack.club/:code
  # Maps domain to campaign and redirects with ref parameter
  CAMPAIGN_HOST_MAP = {
    "flavortown.hack.club" => "https://flavortown.hackclub.com",
    "aces.hack.club" => "https://aces.hackclub.com",
    "construct.hack.club" => "https://construct.hackclub.com",
    "hctg.hack.club" => "https://hctg.hackclub.com"
  }.freeze

  DEFAULT_TARGET = "https://flavortown.hackclub.com"

  def link_referral
    code = params[:code]

    # Determine target URL from host domain
    host = request.host.to_s.downcase
    base_url = CAMPAIGN_HOST_MAP[host] || DEFAULT_TARGET

    # If code is present and valid (alphanumeric, <= 64 chars), append as ref parameter
    if code.present? && code.match?(/^[A-Za-z0-9]+$/) && code.length <= 64
      # Check if this is a poster referral code (8 chars uppercase)
      if code.length == 8 && code.match?(/^[A-Z0-9]+$/)
        poster = Poster.find_by(referral_code: code)
        if poster
          # Set session for poster referral before redirecting
          session[:referral_code] = code
          session[:referral_type] = "poster"
          redirect_to "#{base_url}/", allow_other_host: true
          return
        end
      end

      redirect_url = "#{base_url}/?ref=#{CGI.escape(code)}"
    else
      # Invalid or missing code - just redirect to base domain
      redirect_url = "#{base_url}/"
    end

    redirect_to redirect_url, allow_other_host: true
  end

  # Proxy Slack avatars with aggressive browser caching to avoid 429 rate limits
  def avatar
    url = params[:url]

    unless url.present? && url.start_with?("https://")
      head :bad_request
      return
    end

    # Generate ETag from URL for conditional requests
    etag = Digest::MD5.hexdigest(url)

    # Check if client has cached version
    if request.headers["If-None-Match"] == etag
      head :not_modified
      return
    end

    # Fetch the image from Slack CDN
    begin
      response = Faraday.get(url) do |req|
        req.options.timeout = 10
      end

      if response.success?
        # Set aggressive caching headers (1 year)
        expires_in 1.year, public: true
        response.headers["ETag"] = etag
        response.headers["Cache-Control"] = "public, max-age=31536000, immutable"

        send_data response.body,
                  type: response.headers["Content-Type"] || "image/jpeg",
                  disposition: "inline"
      else
        head :not_found
      end
    rescue Faraday::Error => e
      Rails.logger.error("Avatar proxy failed: #{e.message}")
      head :bad_gateway
    end
  end
end
