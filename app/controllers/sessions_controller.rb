# frozen_string_literal: true

class SessionsController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :new, :create, :failure ]

  def new
    state = SecureRandom.hex(24)
    session[:oauth_state] = state

    redirect_uri = auth_callback_url
    authorize_url = HackClubAuthService.authorize_url(redirect_uri: redirect_uri, state: state)

    redirect_to authorize_url, allow_other_host: true
  rescue HackClubAuthService::AuthenticationError => e
    Rails.logger.error("Auth init failed: #{e.message}")
    redirect_to root_path, alert: t("auth.flash.auth_failed_with_message", message: e.message)
  rescue StandardError => e
    Rails.logger.error("Auth init failed: #{e.message}")
    redirect_to root_path, alert: t("auth.flash.auth_failed_generic")
  end

  def create
    if params[:state] != session[:oauth_state]
      Rails.logger.error("OAuth state mismatch")
      session.delete(:oauth_state)
      return redirect_to root_path, alert: t("auth.flash.auth_failed_generic")
    end

    session.delete(:oauth_state)

    begin
      token_response = HackClubAuthService.exchange_code(
        code: params[:code],
        redirect_uri: auth_callback_url
      )

      user_info = HackClubAuthService.fetch_user_info(token_response["access_token"])

      # Get signup ref from cookie for new users
      signup_ref = cookies[:signup_ref]
      user = HackClubAuthService.find_or_create_user(user_info, signup_ref: signup_ref)

      # Capture signup ref source from cookie if this is a new user
      capture_signup_ref_source(user)

      session[:user_id] = user.id
      session[:hc_auth_token] = token_response["access_token"]

      # Log the login with IP and user agent
      log_login(user)

      Rails.logger.info("User #{user.id} (#{user.slack_id}) signed in")

      # Create referral if user came via referral link
      create_referral_from_session(user)

      # Redirect to stored path or default campaign
      return_path = session.delete(:return_to)
      redirect_path = if return_path.present? && return_path.start_with?("/c/")
        return_path
      else
        campaign_path(current_campaign.slug)
      end

      redirect_to redirect_path, notice: t("auth.flash.welcome", name: user.display_name)
    rescue HackClubAuthService::AuthenticationError => e
      Rails.logger.error("Authentication error: #{e.message}")
      redirect_to root_path, alert: t("auth.flash.auth_failed_with_message", message: e.message)
    rescue StandardError => e
      Rails.logger.error("Unexpected auth error: #{e.message}")
      redirect_to root_path, alert: t("auth.flash.generic_error")
    end
  end

  def failure
    redirect_to root_path, alert: t("auth.flash.cancelled")
  end

  def destroy
    Rails.logger.info("User #{current_user&.id} signed out")
    session.delete(:user_id)
    redirect_to root_path, notice: t("flash.signed_out")
  end

  private

  def log_login(user)
    LoginLog.create!(
      user: user,
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
    # Login logging is non-critical - don't block user login
    Rails.logger.error("Failed to log login for user #{user.id}: #{e.message}")
  end

  def create_referral_from_session(referred_user)
    ReferralFromSessionService.new(
      referred_user: referred_user,
      referral_code: session[:referral_code],
      referral_type: session[:referral_type],
      campaign: current_campaign
    ).call

    session.delete(:referral_code)
    session.delete(:referral_type)
  end

  def capture_signup_ref_source(user)
    return unless cookies[:signup_ref].present?

    ref_value = cookies[:signup_ref].to_s.strip
    return if ref_value.blank?

    # Skip if column doesn't exist yet (migration not run)
    return unless user.respond_to?(:signup_ref_source)
    return if user.signup_ref_source.present?

    user.update_column(:signup_ref_source, ref_value)
    cookies.delete(:signup_ref)
    Rails.logger.info("Captured signup ref source for user #{user.id}: #{ref_value}")
  rescue ActiveRecord::ActiveRecordError => e
    # Signup ref capture is non-critical - don't block user login
    Rails.logger.error("Failed to capture signup ref source for user #{user.id}: #{e.message}")
  end
end
