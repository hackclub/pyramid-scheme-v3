# frozen_string_literal: true

module Admin
  class GeoController < BaseController
    def index
      @tab = params[:tab] || "proxy"
      @date_range = params[:date_range] || "all"
      @search = params[:search]

      # Build base queries with optional date filtering
      base_scope = apply_date_filter(@date_range)

      case @tab
      when "proxy"
        scope = ReferralCodeLog.geocoded.recent
        scope = scope.where("created_at >= ?", base_scope) if base_scope
        scope = scope.where("ip_address ILIKE ? OR referral_code ILIKE ?", "%#{@search}%", "%#{@search}%") if @search.present?

        @pagy, @records = pagy(scope, limit: 50)

        country_scope = ReferralCodeLog.geocoded
        country_scope = country_scope.where("created_at >= ?", base_scope) if base_scope
        @country_stats = country_scope
          .group(:country_code, :country_name)
          .order("count_all DESC")
          .limit(20)
          .count

        # Get map coordinates (limit to recent 500 for performance)
        @map_data = country_scope.where.not(latitude: nil, longitude: nil)
          .order(created_at: :desc)
          .limit(500)
          .pluck(:latitude, :longitude, :city, :country_name, :referral_code)

      when "logins"
        scope = LoginLog.geocoded.recent.includes(:user)
        scope = scope.where("login_logs.created_at >= ?", base_scope) if base_scope
        scope = scope.where("ip_address ILIKE ?", "%#{@search}%") if @search.present?

        @pagy, @records = pagy(scope, limit: 50)

        country_scope = LoginLog.geocoded
        country_scope = country_scope.where("created_at >= ?", base_scope) if base_scope
        @country_stats = country_scope
          .group(:country_code, :country_name)
          .order("count_all DESC")
          .limit(20)
          .count

        # Get map coordinates with user info
        @map_data = country_scope.where.not(latitude: nil, longitude: nil)
          .joins(:user)
          .order(created_at: :desc)
          .limit(500)
          .pluck(:latitude, :longitude, :city, :country_name, "users.display_name")

      when "posters"
        scope = PosterScan.order(created_at: :desc).includes(poster: :user)
        scope = scope.where("poster_scans.created_at >= ?", base_scope) if base_scope
        scope = scope.where("ip_address ILIKE ?", "%#{@search}%") if @search.present?

        @pagy, @records = pagy(scope, limit: 50)

        country_scope = PosterScan.where.not(country_code: nil)
        country_scope = country_scope.where("created_at >= ?", base_scope) if base_scope
        @country_stats = country_scope
          .group(:country_code)
          .order("count_all DESC")
          .limit(20)
          .count

        # For poster scans, we don't have lat/long but we can show country-level data
        @map_data = []

      when "activity"
        # Check if last_seen_at column exists (migration may not have run yet)
        if User.column_names.include?("last_seen_at")
          scope = User.geocoded.where.not(last_seen_at: nil).order(last_seen_at: :desc)
          scope = scope.where("last_seen_at >= ?", base_scope) if base_scope
          scope = scope.where("display_name ILIKE ? OR email ILIKE ?", "%#{@search}%", "%#{@search}%") if @search.present?

          @pagy, @records = pagy(scope, limit: 50)

          # Get geographic distribution of active users
          country_scope = User.geocoded.where.not(last_seen_at: nil)
          country_scope = country_scope.where("last_seen_at >= ?", base_scope) if base_scope
          @country_stats = country_scope
            .group(:country_code, :country_name)
            .order("count_all DESC")
            .limit(20)
            .count

          # Get map coordinates for active users
          @map_data = country_scope.where.not(latitude: nil, longitude: nil)
            .order(last_seen_at: :desc)
            .limit(500)
            .pluck(:latitude, :longitude, :city, :country_name, :display_name)
        else
          # Migration not run yet, show empty state
          @pagy, @records = pagy(User.none, limit: 50)
          @country_stats = {}
          @map_data = []
        end
      end

      # Calculate summary stats with date filtering
      proxy_scope = ReferralCodeLog.geocoded
      login_scope = LoginLog.geocoded
      user_scope = User.geocoded.where.not(last_seen_at: nil)
      proxy_scope = proxy_scope.where("created_at >= ?", base_scope) if base_scope
      login_scope = login_scope.where("created_at >= ?", base_scope) if base_scope
      user_scope = user_scope.where("last_seen_at >= ?", base_scope) if base_scope && User.column_names.include?("last_seen_at")

      @total_geocoded = proxy_scope.count + login_scope.count + user_scope.count
      @pending_geocoding = ReferralCodeLog.not_geocoded.count + LoginLog.not_geocoded.count + User.not_geocoded.where.not(last_ip_address: nil).count

      # Get unique countries count
      @countries_count = @country_stats&.keys&.size || 0

      # Get recent geocode runs for monitoring
      @geocode_runs = GeocodeRun.recent.limit(10)

      # Calculate activity stats for better presentation
      @total_records = case @tab
      when "proxy"
        base = ReferralCodeLog.all
        base = base.where("created_at >= ?", base_scope) if base_scope
        base.count
      when "logins"
        base = LoginLog.all
        base = base.where("created_at >= ?", base_scope) if base_scope
        base.count
      when "posters"
        base = PosterScan.all
        base = base.where("created_at >= ?", base_scope) if base_scope
        base.count
      when "activity"
        if User.column_names.include?("last_seen_at")
          base = User.where.not(last_seen_at: nil)
          base = base.where("last_seen_at >= ?", base_scope) if base_scope
          base.count
        else
          0
        end
      end
    end

    private

    def apply_date_filter(range)
      case range
      when "today"
        Time.current.beginning_of_day
      when "week"
        1.week.ago
      when "month"
        1.month.ago
      when "year"
        1.year.ago
      else
        nil
      end
    end
  end
end
