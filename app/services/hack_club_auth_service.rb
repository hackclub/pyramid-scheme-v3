# frozen_string_literal: true

# Service for authenticating users via Hack Club OAuth.
#
# Handles the OAuth 2.0 authorization code flow with Hack Club Auth,
# including token exchange, user info fetching, and user creation/updates.
# Also integrates with Slack API to fetch enhanced profile data.
#
# @example Generate authorization URL
#   url = HackClubAuthService.authorize_url(
#     redirect_uri: "https://example.com/callback",
#     state: "random_state_token"
#   )
#
# @example Exchange authorization code for user info
#   tokens = HackClubAuthService.exchange_code(code: params[:code], redirect_uri: redirect_url)
#   user_info = HackClubAuthService.fetch_user_info(tokens["access_token"])
#   user = HackClubAuthService.find_or_create_user(user_info)
class HackClubAuthService
  AUTHORIZE_URL = "https://auth.hackclub.com/oauth/authorize"
  TOKEN_URL = "https://auth.hackclub.com/oauth/token"
  USER_INFO_URL = "https://auth.hackclub.com/api/v1/me"

  DEFAULT_SCOPES = "email profile address verification_status slack_id"

  class AuthenticationError < StandardError; end

  def self.authorize_url(redirect_uri:, state:)
    scopes = ENV.fetch("HC_AUTH_SCOPES", DEFAULT_SCOPES).to_s.strip
    params = {
      client_id: client_id,
      redirect_uri: redirect_uri,
      response_type: "code",
      # HCAuth scopes gate fields in /api/v1/me.
      # The OAuth app registered on auth.hackclub.com must be configured to allow
      # whatever scopes we request here.
      # See ref/auth: app/views/api/v1/identities/_identity.jb
      scope: scopes,
      state: state
    }

    "#{AUTHORIZE_URL}?#{params.to_query}"
  end

  def self.exchange_code(code:, redirect_uri:)
    response = connection.post(TOKEN_URL) do |req|
      req.body = {
        client_id: client_id,
        client_secret: client_secret,
        code: code,
        redirect_uri: redirect_uri,
        grant_type: "authorization_code"
      }
    end

    unless response.success?
      Rails.logger.error("HC Auth token exchange failed: Status #{response.status}, Body: #{response.body}")
      raise AuthenticationError, "OAuth configuration error. Please ensure the callback URL #{redirect_uri} is registered in your Hack Club OAuth app settings."
    end

    begin
      result = JSON.parse(response.body)
    rescue JSON::ParserError => e
      Rails.logger.error("HC Auth received non-JSON response: #{response.body}")
      raise AuthenticationError, "OAuth configuration error. Received HTML instead of JSON. Check that redirect_uri matches registered callback."
    end

    result
  end

  def self.fetch_user_info(access_token)
    raise AuthenticationError, "Missing access token from Hack Club Auth" if access_token.blank?

    response = connection.get(USER_INFO_URL) do |req|
      req.headers["Authorization"] = "Bearer #{access_token}"
      req.headers["Accept"] = "application/json"
    end

    begin
      result = JSON.parse(response.body)
    rescue JSON::ParserError
      Rails.logger.error("HC Auth user info parse failed: Status #{response.status}, Body: #{response.body}")
      raise AuthenticationError, "Received an unexpected response from Hack Club Auth. Please try again."
    end

    unless response.success?
      Rails.logger.error("HC Auth user info fetch failed: Status #{response.status}, Body: #{result}")
      message = result["error"] || result["message"] || "Failed to fetch user info"
      raise AuthenticationError, message
    end

    normalize_user_info(result)
  end

  def self.fetch_addresses(access_token)
    raise AuthenticationError, "Missing access token from Hack Club Auth" if access_token.blank?

    response = connection.get(USER_INFO_URL) do |req|
      req.headers["Authorization"] = "Bearer #{access_token}"
      req.headers["Accept"] = "application/json"
    end

    begin
      result = JSON.parse(response.body)
    rescue JSON::ParserError
      Rails.logger.error("HC Auth addresses parse failed: Status #{response.status}, Body: #{response.body}")
      return []
    end

    unless response.success?
      Rails.logger.error("HC Auth addresses fetch failed: Status #{response.status}, Body: #{result}")

      # Let callers surface a re-auth link when the token is no longer valid.
      if [ 401, 403 ].include?(response.status)
        message = result["error"] || result["message"] || "Hack Club Auth token expired"
        raise AuthenticationError, message
      end

      return []
    end

    # addresses come from the identity object when address scope is included
    identity = result["identity"] || result
    identity["addresses"] || []
  end

  # Extracts the country code from the user's primary address
  # @param access_token [String] HC Auth access token
  # @return [String, nil] ISO country code (e.g., "US", "CA") or nil if not found
  def self.fetch_primary_address_country(access_token)
    addresses = fetch_addresses(access_token)
    return nil if addresses.empty?

    # Find the primary address or use the first one
    primary_address = addresses.find { |addr| addr["primary"] == true } || addresses.first
    return nil unless primary_address

    # Extract country code from the address
    primary_address["country"]
  rescue => e
    Rails.logger.error("Failed to fetch primary address country: #{e.message}")
    nil
  end

  # Finds an existing user or creates a new one from OAuth user info.
  #
  # Attempts to fetch enhanced profile data from Slack if available,
  # falling back to Hack Club Auth profile data.
  #
  # @param user_info [Hash] Normalized user info from #fetch_user_info
  # @param signup_ref [String, nil] Optional referral code from cookie
  # @return [User] The found or created user
  # @raise [AuthenticationError] If email is missing from user_info
  def self.find_or_create_user(user_info, signup_ref: nil)
    slack_id = user_info["slack_id"]
    email = user_info["email"]&.downcase&.strip

    raise AuthenticationError, "Missing email from Hack Club Auth" if email.blank?

    profile = fetch_profile_with_fallback(slack_id: slack_id, user_info: user_info)

    display_name = profile["display_name"].presence ||
                   profile["real_name"].presence ||
                   email.split("@").first
    avatar = profile["avatar"]

    # Find user by slack_id first, then fall back to email lookup
    user = User.find_by(slack_id: slack_id) if slack_id.present?
    user ||= User.find_by(email: email)

    # If user exists, always update from Slack profile if available
    if user
      update_attrs = { email: email }

      # Update slack_id if user was found by email but didn't have one
      if slack_id.present? && user.slack_id.blank?
        update_attrs[:slack_id] = slack_id
        Rails.logger.info("Updating user #{user.id} with slack_id: #{slack_id}")
      end

      # Always update display_name and avatar from Slack if available
      if profile
        update_attrs[:display_name] = display_name
        update_attrs[:avatar] = avatar if avatar.present?
        update_attrs[:first_name] = profile["first_name"] if profile["first_name"].present?
        update_attrs[:last_name] = profile["last_name"] if profile["last_name"].present?

        Rails.logger.info("Updating user #{user.id} profile from Slack: #{display_name}")
      end

      user.update!(update_attrs)
      return user
    end

    # Only set profile data on user creation
    attributes = {
      email: email,
      display_name: display_name,
      avatar: avatar,
      first_name: profile["first_name"],
      last_name: profile["last_name"]
    }

    # Add immutable signup_ref_source from cookie if present
    attributes[:signup_ref_source] = signup_ref if signup_ref.present?

    User.create!(attributes.merge(slack_id: slack_id, role: :user))
  end

  def self.client_id
    ENV.fetch("HC_AUTH_CLIENT_ID") do
      raise AuthenticationError, "HC_AUTH_CLIENT_ID not configured"
    end
  end

  def self.client_secret
    ENV.fetch("HC_AUTH_SECRET") do
      raise AuthenticationError, "HC_AUTH_SECRET not configured"
    end
  end

  def self.fetch_slack_profile(slack_id)
    # Use Slack Bot API directly with bot token
    bot_token = ENV["SLACK_BOT_TOKEN"]

    unless bot_token.present?
      Rails.logger.warn("SLACK_BOT_TOKEN not configured, skipping Slack profile fetch")
      raise AuthenticationError, "Slack Bot Token not configured"
    end

    response = connection.get("https://slack.com/api/users.info") do |req|
      req.params["user"] = slack_id
      req.headers["Authorization"] = "Bearer #{bot_token}"
      req.headers["Content-Type"] = "application/json"
    end

    begin
      result = JSON.parse(response.body)
    rescue JSON::ParserError
      Rails.logger.error("Slack API parse failed: Status #{response.status}, Body: #{response.body}")
      raise AuthenticationError, "Failed to fetch profile from Slack"
    end

    unless response.success? && result["ok"]
      error_msg = result["error"] || "Unknown error"
      Rails.logger.info("Slack API error for #{slack_id}: #{error_msg}")
      raise AuthenticationError, "Failed to fetch profile from Slack: #{error_msg}"
    end

    user = result["user"]
    profile = user["profile"] || {}

    {
      "display_name" => profile["display_name"].presence || user["real_name"],
      "real_name" => user["real_name"],
      "first_name" => profile["first_name"],
      "last_name" => profile["last_name"],
      "avatar" => profile["image_512"] || profile["image_192"] || profile["image_72"]
    }
  end

  def self.normalize_user_info(raw_response)
    identity = raw_response["identity"] || raw_response

    raise AuthenticationError, "Missing identity data from Hack Club Auth" if identity.blank?

    first_name = identity["given_name"].presence || identity["first_name"].presence
    last_name = identity["family_name"].presence || identity["last_name"].presence
    display_name = identity["nickname"].presence || identity["name"].presence || [ first_name, last_name ].compact_blank.join(" ").presence

    {
      "slack_id" => identity["slack_id"],
      "email" => identity["primary_email"] || identity["email"],
      "display_name" => display_name,
      "avatar" => identity["picture"],
      "first_name" => first_name,
      "last_name" => last_name
    }
  end

  def self.connection
    @connection ||= Faraday.new do |f|
      f.request :url_encoded
      f.adapter Faraday.default_adapter
    end
  end

  # Fetches profile data from Slack API or falls back to HC Auth data.
  #
  # @param slack_id [String, nil] The user's Slack ID
  # @param user_info [Hash] The user info from HC Auth (fallback)
  # @return [Hash] Profile data with display_name, first_name, last_name, avatar
  # @api private
  def self.fetch_profile_with_fallback(slack_id:, user_info:)
    return fallback_profile(user_info) unless slack_id.present?

    begin
      fetch_slack_profile(slack_id)
    rescue AuthenticationError => e
      Rails.logger.info("Slack profile fetch failed for #{slack_id}: #{e.message}, using HC Auth profile fallback")
      fallback_profile(user_info)
    end
  end
  private_class_method :fetch_profile_with_fallback

  # Builds a profile hash from HC Auth user info.
  #
  # @param user_info [Hash] The user info from HC Auth
  # @return [Hash] Profile data
  # @api private
  def self.fallback_profile(user_info)
    {
      "display_name" => user_info["display_name"],
      "first_name" => user_info["first_name"],
      "last_name" => user_info["last_name"],
      "avatar" => user_info["avatar"]
    }
  end
  private_class_method :fallback_profile
end
