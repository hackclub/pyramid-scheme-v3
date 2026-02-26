# frozen_string_literal: true

module Admin
  class ReferralSourcesController < BaseController
    def index
      @search_query = params[:search].to_s.strip

      # Base query: users with signup_ref_source
      scope = User.where.not(signup_ref_source: nil)

      # Apply search filter if present
      if @search_query.present?
        scope = scope.where(
          "signup_ref_source ILIKE ? OR display_name ILIKE ? OR email ILIKE ?",
          "%#{@search_query}%",
          "%#{@search_query}%",
          "%#{@search_query}%"
        )
      end

      # Group by signup_ref_source and count
      @ref_stats = scope
        .group(:signup_ref_source)
        .select(
          :signup_ref_source,
          "COUNT(*) as user_count",
          "MIN(created_at) as first_signup",
          "MAX(created_at) as last_signup"
        )
        .order(Arel.sql("COUNT(*) DESC, signup_ref_source ASC"))

      # If specific ref source is selected, show user details
      @selected_ref = params[:ref].to_s.strip
      if @selected_ref.present?
        @users = User
          .where(signup_ref_source: @selected_ref)
          .order(created_at: :desc)
          .includes(:user_emblems)
          .limit(100)
      end

      # Click counts from ref source tracking
      if @search_query.present?
        click_scope = RefSourceClick.where("ref_source ILIKE ?", "%#{@search_query}%")
      else
        click_scope = RefSourceClick.all
      end
      @click_counts = click_scope.click_counts
      @unique_click_counts = click_scope.unique_click_counts
      @total_clicks = RefSourceClick.count
      @total_unique_clicks = RefSourceClick.distinct.count(:ip_address)

      # Sources that have clicks but no signups yet
      signup_sources = @ref_stats.map(&:signup_ref_source)
      @click_only_sources = @click_counts.reject { |source, _| signup_sources.include?(source) }
        .sort_by { |_, count| -count }

      # Overall stats
      @total_users_with_ref = User.where.not(signup_ref_source: nil).count
      @total_users = User.count
      @percentage_with_ref = (@total_users_with_ref.to_f / @total_users * 100).round(1)
    end
  end
end
