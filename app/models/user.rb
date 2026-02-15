# frozen_string_literal: true

class User < ApplicationRecord
  include Geocodable

  enum :role, { user: 0, fulfiller: 1, admin: 2 }

  has_many :referrals_given, class_name: "Referral", foreign_key: :referrer_id, dependent: :destroy, inverse_of: :referrer
  has_many :referrals_received, class_name: "Referral", foreign_key: :referred_id, dependent: :nullify, inverse_of: :referred
  has_many :posters, dependent: :destroy, inverse_of: :user
  has_many :poster_groups, dependent: :destroy, inverse_of: :user
  has_many :shard_transactions, dependent: :destroy, inverse_of: :user
  has_many :shop_orders, dependent: :destroy, inverse_of: :user
  has_many :user_emblems, dependent: :destroy, inverse_of: :user
  has_many :video_submissions, dependent: :destroy, inverse_of: :user
  has_many :campaigns, through: :user_emblems
  has_many :login_logs, dependent: :destroy, inverse_of: :user

  validates :slack_id, uniqueness: true, allow_nil: true
  validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :display_name, presence: true, length: { maximum: 100 }
  validates :role, presence: true
  validates :referral_code, uniqueness: true, allow_nil: true
  validates :custom_referral_code, uniqueness: { case_sensitive: false }, allow_nil: true
  validates :custom_referral_code, length: { minimum: 3, maximum: 64 }, allow_nil: true
  validates :custom_referral_code, format: { with: /\A[a-zA-Z]+\z/, message: "must contain only letters (a-z, A-Z)" }, allow_nil: true

  before_validation { self.email = email.to_s.downcase.strip }
  before_validation :generate_referral_code, on: :create

  scope :on_leaderboard, -> { where(leaderboard_opted_out: false, is_banned: false) }
  scope :for_leaderboard, -> { where(is_banned: false) }  # Includes opted-out users for redacted display
  scope :by_referrals, -> { order(referral_count: :desc) }
  scope :by_posters, -> { order(poster_count: :desc) }
  scope :by_shards, -> { order(total_shards: :desc) }
  scope :admins, -> { where(role: :admin) }
  scope :banned, -> { where(is_banned: true) }
  scope :active, -> { where(is_banned: false) }
  scope :with_referral_code, -> { where.not(referral_code: nil) }
  scope :with_custom_referral_code, -> { where.not(custom_referral_code: nil) }
  scope :created_this_week, -> { where(created_at: Time.current.beginning_of_week..Time.current.end_of_week) }
  scope :search, ->(query) {
    return all if query.blank?

    fuzzy_query = "%#{query}%".downcase
    where(
      "LOWER(display_name) ILIKE ? OR LOWER(email) ILIKE ? OR LOWER(slack_id) = ?",
      fuzzy_query, fuzzy_query, query.downcase
    )
  }

  # Find a user by any referral code (standard or custom)
  def self.find_by_any_referral_code(code)
    return nil if code.blank?

    # Try standard referral code (8-char alphanumeric)
    if code.match?(/^[A-Z0-9]{8}$/i)
      user = find_by(referral_code: code.upcase)
      return user if user
    end

    # Try custom referral code (letters only, 3-64 chars)
    if code.match?(/^[a-zA-Z]{3,64}$/)
      user = find_by("LOWER(custom_referral_code) = ?", code.downcase)
      return user if user
    end

    nil
  end

  def admin?
    role == "admin"
  end

  def fulfiller?
    role == "fulfiller" || admin?
  end

  def credit_shards!(amount, transaction_type:, transactable: nil, description: nil)
    transaction do
      new_balance = total_shards + amount
      shard_transactions.create!(
        amount: amount,
        transaction_type: transaction_type,
        transactable: transactable,
        description: description,
        balance_after: new_balance
      )
      update!(total_shards: new_balance)
    end
  end

  def debit_shards!(amount, transaction_type:, transactable: nil, description: nil)
    raise InsufficientShardsError, "Not enough shards" if total_shards < amount

    credit_shards!(-amount, transaction_type: transaction_type, transactable: transactable, description: description)
  end

  def can_afford?(amount)
    total_shards >= amount
  end

  def emblems_for_campaign(campaign)
    user_emblems.where(campaign: campaign)
  end

  def participated_in?(campaign)
    user_emblems.exists?(campaign: campaign)
  end

  def ban!(reason: nil, internal_reason: nil)
    update!(
      is_banned: true,
      banned_at: Time.current,
      banned_reason: reason,
      internal_ban_reason: internal_reason
    )
  end

  def unban!
    update!(
      is_banned: false,
      banned_at: nil,
      banned_reason: nil,
      internal_ban_reason: nil
    )
  end

  # Get user's region based on saved preference, country, or fallback to XX
  def effective_region
    return region if region.present? && Shop::Regionalizable::REGION_CODES.include?(region)

    # Try to infer from country code
    if country_code.present?
      inferred = Shop::Regionalizable.country_to_region(country_code)
      return inferred if inferred != "XX"
    end

    "XX"
  end

  def update_region!(new_region)
    new_region = new_region.to_s.upcase
    return false unless Shop::Regionalizable::REGION_CODES.include?(new_region)

    update!(region: new_region)
  end

  # Custom referral code methods
  CUSTOM_REFERRAL_CODE_CHANGE_COST = 3

  def has_custom_referral_code?
    custom_referral_code.present?
  end

  def custom_referral_code_is_free?
    !has_custom_referral_code?
  end

  def custom_referral_code_change_cost
    custom_referral_code_is_free? ? 0 : CUSTOM_REFERRAL_CODE_CHANGE_COST
  end

  def can_change_custom_referral_code?
    custom_referral_code_is_free? || can_afford?(CUSTOM_REFERRAL_CODE_CHANGE_COST)
  end

  def effective_referral_code
    custom_referral_code.presence || referral_code
  end

  def set_custom_referral_code!(new_code)
    raise ArgumentError, "Code cannot be blank" if new_code.blank?
    raise InsufficientShardsError, "Not enough shards" unless can_change_custom_referral_code?

    transaction do
      # Charge shards if this is a change (not first time)
      unless custom_referral_code_is_free?
        debit_shards!(
          CUSTOM_REFERRAL_CODE_CHANGE_COST,
          transaction_type: :custom_link_change,
          description: "Changed custom referral link to '#{new_code}'"
        )
      end

      update!(
        custom_referral_code: new_code,
        custom_referral_code_changed_at: Time.current
      )
    end
  end

  class InsufficientShardsError < StandardError; end

  # Weekly paid poster constants
  # Users can create unlimited posters, but only get shards for the first X per week
  BASE_WEEKLY_PAID_POSTERS = 10
  PAID_POSTER_BONUS_PER_REFERRAL = 5

  # Calculate the paid poster limit for the current week
  # Base: 10 + 5 for each completed referral (permanent bonus) + admin bonus
  # Memoized for performance (prevents multiple calculations in views)
  def weekly_paid_poster_limit
    @weekly_paid_poster_limit ||= BASE_WEEKLY_PAID_POSTERS + total_referral_bonus + (bonus_paid_posters || 0)
  end

  # Calculate bonus from all completed referrals (permanent, not just this week)
  def total_referral_bonus
    @total_referral_bonus ||= (referral_count || 0) * PAID_POSTER_BONUS_PER_REFERRAL
  end

  # Alias for backwards compatibility
  alias_method :weekly_poster_limit, :weekly_paid_poster_limit

  # Count posters created this calendar week (Monday to Sunday)
  # Excludes rejected posters so they don't count against quota
  def posters_created_this_week
    @posters_created_this_week ||= posters
      .where(created_at: Time.current.beginning_of_week..Time.current.end_of_week)
      .where.not(verification_status: "rejected")
      .count
  end

  # Count completed referrals this calendar week (Monday to Sunday)
  def completed_referrals_this_week
    @completed_referrals_this_week ||= referrals_given.completed.where(completed_at: Time.current.beginning_of_week..Time.current.end_of_week).count
  end

  # How many paid posters remaining this week
  def remaining_paid_posters_this_week
    [ weekly_paid_poster_limit - posters_created_this_week, 0 ].max
  end

  # Alias for backwards compatibility
  alias_method :remaining_posters_this_week, :remaining_paid_posters_this_week

  # Check if user will receive shards for the next poster
  def next_poster_will_be_paid?
    posters_created_this_week < weekly_paid_poster_limit
  end

  private

  def generate_referral_code
    self.referral_code ||= loop do
      code = SecureRandom.alphanumeric(8).upcase
      break code unless User.exists?(referral_code: code)
    end
  end
end
