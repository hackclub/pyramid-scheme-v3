# frozen_string_literal: true

class ReferralLeaderboardCashoutService
  PAYOUT_DESCRIPTION_PREFIX = "Referral leaderboard payout".freeze

  Result = Struct.new(:period, :awards, keyword_init: true)

  def initialize(period: ReferralLeaderboardPeriod.previous, apply: false)
    @period = period
    @apply = apply
  end

  def call
    awards = prizes.map do |user_id, prize|
      user = leaders_by_id.fetch(user_id)
      description = payout_description(prize[:rank])
      already_paid = user.shard_transactions.exists?(transaction_type: "admin_grant", description: description)

      if apply && !already_paid
        user.credit_shards!(
          prize[:shards],
          transaction_type: "admin_grant",
          description: description
        )
      end

      {
        user_id: user.id,
        display_name: user.display_name,
        rank: prize[:rank],
        shards: prize[:shards],
        status: already_paid ? :already_paid : (apply ? :paid : :pending)
      }
    end

    Result.new(period: period, awards: awards)
  end

  private

  attr_reader :period, :apply

  def prizes
    @prizes ||= LeaderboardRankingService
      .new(leaders: leaders, category: "referrals", page: 1)
      .calculate_prizes(ranks)
  end

  def ranks
    @ranks ||= LeaderboardRankingService
      .new(leaders: leaders, category: "referrals", page: 1)
      .calculate_ranks
  end

  def leaders
    @leaders ||= ReferralLeaderboardQuery
      .new(base_scope: User.active, period: period)
      .call
      .to_a
      .select { |user| user.leaderboard_referral_count.to_i.positive? }
  end

  def leaders_by_id
    @leaders_by_id ||= leaders.index_by(&:id)
  end

  def payout_description(rank)
    "#{PAYOUT_DESCRIPTION_PREFIX}: #{period.payout_label} (rank #{rank})"
  end
end
