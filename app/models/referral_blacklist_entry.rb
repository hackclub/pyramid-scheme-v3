# frozen_string_literal: true

# Blocks specific referral relationships from being created or progressed.
# Use cases:
# - Block self-referrals that sneak through via Airtable sync
# - Block known abusive referrer/referred pairs
# - Block all referrals from a specific referrer (spammer)
# - Block all referrals for a specific referred person (alt account)
class ReferralBlacklistEntry < ApplicationRecord
  BLOCK_TYPES = %w[pair referrer referred custom_code].freeze

  belongs_to :created_by, class_name: "User", optional: true

  before_validation :normalize_identifiers

  validates :block_type, presence: true, inclusion: { in: BLOCK_TYPES }
  validates :reason, presence: true
  validates :referrer_identifier, presence: true, if: -> { block_type.in?(%w[pair referrer custom_code]) }
  validates :referred_identifier, presence: true, if: -> { block_type.in?(%w[pair referred]) }
  validate :ensure_unique_active_custom_code_block, if: :active_custom_code_block?

  scope :active, -> { where(active: true) }
  scope :pairs, -> { where(block_type: "pair") }
  scope :referrer_blocks, -> { where(block_type: "referrer") }
  scope :referred_blocks, -> { where(block_type: "referred") }
  scope :custom_code_blocks, -> { where(block_type: "custom_code") }

  # Check if a specific referrer→referred pair is blacklisted
  # Checks all three block types: exact pair, referrer-wide, referred-wide
  def self.blocked?(referrer_identifier:, referred_identifier:)
    active.where(
      "(block_type = 'pair' AND LOWER(referrer_identifier) = :referrer AND LOWER(referred_identifier) = :referred) OR " \
      "(block_type = 'referrer' AND LOWER(referrer_identifier) = :referrer) OR " \
      "(block_type = 'referred' AND LOWER(referred_identifier) = :referred)",
      referrer: referrer_identifier.to_s.downcase,
      referred: referred_identifier.to_s.downcase
    ).exists?
  end

  # Check if a referrer is globally blocked
  def self.referrer_blocked?(identifier)
    active.where(block_type: "referrer")
          .where("LOWER(referrer_identifier) = ?", identifier.to_s.downcase)
          .exists?
  end

  # Check if a referred person is globally blocked
  def self.referred_blocked?(identifier)
    active.where(block_type: "referred")
          .where("LOWER(referred_identifier) = ?", identifier.to_s.downcase)
          .exists?
  end

  def self.custom_code_blocked?(code)
    normalized_code = normalize_identifier(code)
    return false if normalized_code.blank?

    active.custom_code_blocks
          .where("LOWER(referrer_identifier) = ?", normalized_code)
          .exists?
  end

  # Check all possible identifiers for a user (email, slack_id, user_id) as referrer
  def self.referrer_blocked_any?(user)
    identifiers = [ user.email, user.slack_id, user.id.to_s ].compact
    return false if identifiers.empty?

    conditions = identifiers.map { "LOWER(referrer_identifier) = ?" }.join(" OR ")
    active.where(block_type: "referrer")
          .where(conditions, *identifiers.map(&:downcase))
          .exists?
  end

  def deactivate!
    update!(active: false)
  end

  def reactivate!
    update!(active: true)
  end

  def custom_code
    return unless block_type == "custom_code"

    referrer_identifier
  end

  def custom_code=(value)
    self.referrer_identifier = value
  end

  def custom_code_block?
    block_type == "custom_code"
  end

  def self.normalize_identifier(value)
    value.to_s.strip.downcase
  end

  private

  def normalize_identifiers
    self.referrer_identifier = self.class.normalize_identifier(referrer_identifier).presence
    self.referred_identifier = self.class.normalize_identifier(referred_identifier).presence
  end

  def active_custom_code_block?
    active? && custom_code_block? && referrer_identifier.present?
  end

  def ensure_unique_active_custom_code_block
    return unless self.class.active.custom_code_blocks
                            .where("LOWER(referrer_identifier) = ?", referrer_identifier)
                            .where.not(id: id)
                            .exists?

    errors.add(:custom_code, "has already been blacklisted")
  end
end
