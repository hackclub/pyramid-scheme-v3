# frozen_string_literal: true

# Calculates leaderboard rankings and prize distributions.
#
# Implements dense ranking (1, 1, 2, 2, 3...) where users with the same
# score share a rank, and calculates prize splits for ties.
#
# @example Calculate rankings and prizes
#   service = LeaderboardRankingService.new(
#     leaders: users_with_referrals,
#     category: "referrals",
#     page: 1
#   )
#   ranks = service.calculate_ranks
#   prizes = service.calculate_prizes(ranks)
class LeaderboardRankingService
  # Minimum shards awarded to any prize winner
  MINIMUM_PRIZE_SHARDS = 1

  # Base prize pool amounts for top ranks (before splitting for ties)
  BASE_PRIZES = {
    1 => 50,  # 1st place pool: 50 shards
    2 => 25,  # 2nd place pool: 25 shards
    3 => 10   # 3rd place pool: 10 shards
  }.freeze

  # Initializes the ranking service.
  #
  # @param leaders [Array<User>] Users to rank, must respond to #campaign_referral_count or #referral_count
  # @param category [String] The leaderboard category (currently only "referrals" awards prizes)
  # @param page [Integer] The page number (prizes only awarded on page 1)
  def initialize(leaders:, category:, page:)
    @leaders = leaders
    @category = category
    @page = page
  end

  # Calculates dense rankings (1, 1, 2, 2, 3...) with ties
  # @return [Hash<Integer, Hash>] User ID => { rank:, rank_start: }
  def calculate_ranks
    return {} unless @category == "referrals" && @page == 1

    ranks = {}
    current_rank = 0
    prev_value = nil

    @leaders.each do |user|
      value = extract_referral_count(user)

      # Skip users with 0 referrals - don't assign them a rank
      next if value == 0

      if prev_value.nil? || value != prev_value
        # First user or value changed - increment rank
        current_rank += 1
      end

      ranks[user.id] = { rank: current_rank, rank_start: current_rank }
      prev_value = value
    end

    ranks
  end

  # Calculates prize distribution with splits for ties
  # @param ranks [Hash] Ranks calculated by #calculate_ranks
  # @return [Hash<Integer, Hash>] User ID => { rank:, shards: }
  def calculate_prizes(ranks)
    return {} unless @category == "referrals" && @page == 1

    prizes = {}
    users_with_ranks = @leaders.select { |u| ranks[u.id].present? }

    # Calculate prize amounts for each rank once
    rank_prizes = calculate_rank_prizes(users_with_ranks, ranks)

    # Assign prizes to all users at winning ranks
    users_with_ranks.each do |user|
      rank = ranks[user.id][:rank]
      next unless rank_prizes.key?(rank)

      prizes[user.id] = { rank: rank, shards: rank_prizes[rank] }
    end

    prizes
  end

  private

  def extract_referral_count(user)
    if user.respond_to?(:campaign_referral_count)
      user.campaign_referral_count
    else
      user.referral_count
    end
  end

  def calculate_rank_prizes(users_with_ranks, ranks)
    rank_prizes = {}

    BASE_PRIZES.each do |rank, prize_pool|
      users_at_rank = users_with_ranks.count { |u| ranks[u.id][:rank] == rank }
      next if users_at_rank == 0

      # Everyone at this rank gets at least MINIMUM_PRIZE_SHARDS
      per_person = (prize_pool.to_f / users_at_rank).floor
      rank_prizes[rank] = [ per_person, MINIMUM_PRIZE_SHARDS ].max
    end

    rank_prizes
  end
end
