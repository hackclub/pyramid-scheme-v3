# frozen_string_literal: true

class LeaderboardController < ApplicationController
  def index
    @category = params[:category] || "referrals"
    @search_query = params[:q]

    @pagy, @leaders = pagy(leaderboard_scope, limit: 50)

    # Use service to calculate rankings and prizes
    ranking_service = LeaderboardRankingService.new(
      leaders: @leaders,
      category: @category,
      page: @pagy.page
    )
    @ranks = ranking_service.calculate_ranks
    @referral_prizes = ranking_service.calculate_prizes(@ranks)

    # Giveaway end date (configure as needed)
    @giveaway_end_date = Time.zone.parse("2026-01-30 23:59:59")
  end

  private

  def leaderboard_scope
    base_scope = User.for_leaderboard.search(@search_query)

    case @category
    when "posters"
      base_scope.by_posters
    when "shards"
      base_scope.by_shards
    else
      base_scope.by_referrals
    end
  end
end
