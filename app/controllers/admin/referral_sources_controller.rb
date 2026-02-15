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

      # Overall stats
      @total_users_with_ref = User.where.not(signup_ref_source: nil).count
      @total_users = User.count
      @percentage_with_ref = (@total_users_with_ref.to_f / @total_users * 100).round(1)
    end
  end
end
