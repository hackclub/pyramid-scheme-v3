# frozen_string_literal: true

class ReferralLeaderboardQuery
  def initialize(base_scope:, period: ReferralLeaderboardPeriod.current)
    @base_scope = base_scope
    @period = period
  end

  def call
    base_scope
      .joins(referral_join_sql)
      .group("users.id")
      .select("users.*, COUNT(referrals.id) AS leaderboard_referral_count")
      .order(Arel.sql("COUNT(referrals.id) DESC, users.id ASC"))
  end

  private

  attr_reader :base_scope, :period

  def referral_join_sql
    ActiveRecord::Base.send(
      :sanitize_sql_array,
      [
        <<~SQL.squish,
          LEFT JOIN referrals
            ON referrals.referrer_id = users.id
           AND referrals.status = ?
           AND referrals.completed_at BETWEEN ? AND ?
        SQL
        Referral.statuses[:completed],
        period.starts_at,
        period.ends_at
      ]
    )
  end
end
