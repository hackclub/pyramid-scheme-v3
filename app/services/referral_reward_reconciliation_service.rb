# frozen_string_literal: true

class ReferralRewardReconciliationService
  CORRECTION_DESCRIPTION_PREFIX = "Referral reward reconciliation".freeze

  Result = Struct.new(:corrections, keyword_init: true)

  def initialize(apply: false)
    @apply = apply
  end

  def call
    corrections = outstanding_overpayments.map do |user, overpayment_amount|
      if apply
        user.credit_shards!(
          -overpayment_amount,
          transaction_type: "admin_debit",
          description: correction_description(overpayment_amount)
        )
      end

      user.update!(referral_count: completed_referral_counts[user.id].to_i) if user.referral_count != completed_referral_counts[user.id].to_i

      {
        user_id: user.id,
        display_name: user.display_name,
        overpayment_amount: overpayment_amount,
        resulting_total_shards: apply ? user.reload.total_shards : user.total_shards - overpayment_amount,
        status: apply ? :corrected : :pending
      }
    end

    Result.new(corrections: corrections)
  end

  private

  attr_reader :apply

  def outstanding_overpayments
    users = User.where(id: affected_user_ids).index_by(&:id)

    affected_user_ids.filter_map do |user_id|
      outstanding = positive_referral_amounts[user_id].to_i - expected_referral_amounts[user_id].to_i - prior_corrections[user_id].to_i
      next unless outstanding.positive?

      [ users.fetch(user_id), outstanding ]
    end
  end

  def affected_user_ids
    @affected_user_ids ||= (positive_referral_amounts.keys | expected_referral_amounts.keys | prior_corrections.keys)
  end

  def completed_referral_counts
    @completed_referral_counts ||= Referral.completed.group(:referrer_id).count
  end

  def expected_referral_amounts
    @expected_referral_amounts ||= Referral.completed.includes(:campaign).group_by(&:referrer_id).transform_values do |referrals|
      referrals.sum { |referral| referral.campaign.referral_shards }
    end
  end

  def positive_referral_amounts
    @positive_referral_amounts ||= ShardTransaction.where(transaction_type: "referral")
      .where("amount > 0")
      .group(:user_id)
      .sum(:amount)
  end

  def prior_corrections
    @prior_corrections ||= ShardTransaction.where(transaction_type: "admin_debit")
      .where("description LIKE ?", "#{CORRECTION_DESCRIPTION_PREFIX}:%")
      .group(:user_id)
      .sum(Arel.sql("ABS(amount)"))
  end

  def correction_description(overpayment_amount)
    "#{CORRECTION_DESCRIPTION_PREFIX}: removed #{overpayment_amount} extra referral shard(s)"
  end
end
