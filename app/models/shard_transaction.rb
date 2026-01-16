# frozen_string_literal: true

class ShardTransaction < ApplicationRecord
  belongs_to :user, inverse_of: :shard_transactions
  belongs_to :transactable, polymorphic: true, optional: true

  validates :amount, presence: true, numericality: { other_than: 0 }
  validates :transaction_type, presence: true
  validates :balance_after, presence: true

  TRANSACTION_TYPES = %w[referral poster purchase admin_grant admin_debit refund custom_link_change video video_viral_bonus].freeze

  validates :transaction_type, inclusion: { in: TRANSACTION_TYPES }

  scope :credits, -> { where("amount > 0") }
  scope :debits, -> { where("amount < 0") }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_type, ->(type) { where(transaction_type: type) }
  scope :with_user, -> { includes(:user) }

  def credit?
    amount.positive?
  end

  def debit?
    amount.negative?
  end
end
