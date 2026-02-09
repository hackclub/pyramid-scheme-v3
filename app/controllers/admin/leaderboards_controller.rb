# frozen_string_literal: true

module Admin
  class LeaderboardsController < BaseController
    CATEGORIES = %w[referrals posters shards].freeze

    def index
      @category = params[:category].presence_in(CATEGORIES) || "referrals"
      @search_query = params[:q].to_s.strip

      @pagy, @leaders = pagy(leaderboard_scope, limit: 50)

      ranking_service = LeaderboardRankingService.new(
        leaders: @leaders,
        category: @category,
        page: @pagy.page
      )
      @ranks = ranking_service.calculate_ranks
      @referral_prizes = ranking_service.calculate_prizes(@ranks)

      @giveaway_end_date = Time.zone.parse("2026-02-28 23:59:59")
    end

    private

    def leaderboard_scope
      base_scope = User.active.search(@search_query)

      case @category
      when "posters"
        posters_leaderboard_scope(base_scope)
      when "shards"
        base_scope.by_shards
      else
        base_scope.by_referrals
      end
    end

    def posters_leaderboard_scope(base_scope)
      base_scope
        .joins("LEFT JOIN posters ON posters.user_id = users.id AND posters.verification_status IN ('success', 'approved')")
        .group("users.id")
        .select("users.*, COUNT(posters.id) AS all_time_poster_count")
        .order(Arel.sql("COUNT(posters.id) DESC, users.id ASC"))
    end
  end
end
