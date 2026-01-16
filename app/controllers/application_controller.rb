# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Pagy::Method

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :authenticate_user!
  before_action :enforce_ban
  before_action :track_user_activity
  before_action :capture_ref_param

  helper_method :current_user, :user_signed_in?, :current_campaign, :impersonating?, :impersonator

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def user_signed_in?
    !!current_user
  end

  def current_campaign
    @current_campaign ||= Campaign.find_by(slug: "flavortown") || Campaign.current.first
  end

  # Impersonation helpers
  def impersonating?
    session[:impersonator_id].present?
  end

  def impersonator
    @impersonator ||= User.find_by(id: session[:impersonator_id]) if session[:impersonator_id]
  end

  private

  def authenticate_user!
    return if user_signed_in?

    # Store intended path for redirect after login
    session[:return_to] = request.fullpath if request.get? && !request.xhr?

    respond_to do |format|
      format.html { redirect_to root_path, alert: t("auth.please_sign_in") }
      format.json { render json: { error: t("auth.unauthorized") }, status: :unauthorized }
    end
  end

  def require_login
    authenticate_user!
  end

  def require_admin!
    return if current_user&.admin?

    respond_to do |format|
      format.html { redirect_to root_path, alert: t("auth.access_denied") }
      format.json { render json: { error: t("auth.forbidden") }, status: :forbidden }
    end
  end

  def require_fulfiller!
    return if current_user&.fulfiller?

    respond_to do |format|
      format.html { redirect_to root_path, alert: t("auth.access_denied") }
      format.json { render json: { error: t("auth.forbidden") }, status: :forbidden }
    end
  end

  def enforce_ban
    return unless current_user&.is_banned?
    return if controller_name == "banned" || controller_name == "sessions"

    redirect_to banned_path
  end

  def track_user_activity
    return unless user_signed_in?
    return if current_user.last_seen_at && current_user.last_seen_at > 10.minutes.ago

    updates = { last_seen_at: Time.current }
    should_geocode = false

    # Capture IP address
    ip = request.remote_ip
    if ip.present? && User.column_names.include?("last_ip_address")
      # If IP changed, mark for geocoding
      if current_user.last_ip_address != ip
        updates[:last_ip_address] = ip
        updates[:geocoded_at] = nil if User.column_names.include?("geocoded_at")
        should_geocode = true
      end
    end

    # Capture country code from Cloudflare header
    country = request.headers["CF-IPCountry"]
    updates[:country_code] = country if country.present? && country != "XX"

    current_user.update_columns(updates)

    # Queue geocoding job if IP changed
    GeocodeIpJob.perform_later("User", current_user.id) if should_geocode
  rescue StandardError => e
    # Column doesn't exist yet - migration not run
    Rails.logger.error "Failed to track user activity: #{e.message}"
  end

  def capture_ref_param
    return if user_signed_in?
    return unless params[:ref].present?

    ref_value = params[:ref].to_s.strip
    return if ref_value.blank?

    # Validate format: alphanumeric + dash, up to 64 chars, case-sensitive
    return unless ref_value.match?(/\A[a-zA-Z0-9-]{1,64}\z/)

    cookies[:signup_ref] = {
      value: ref_value,
      expires: 30.days.from_now,
      httponly: true
    }
  end
end
