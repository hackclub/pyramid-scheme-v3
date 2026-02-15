# frozen_string_literal: true

class PosterGroup < ApplicationRecord
  MAX_POSTERS_PER_GROUP = 10
  CHARSETS = %w[alphanumeric numeric alpha].freeze

  belongs_to :user, inverse_of: :poster_groups
  belongs_to :campaign, inverse_of: false
  has_many :posters, dependent: :nullify, inverse_of: :poster_group

  validates :charset, inclusion: { in: CHARSETS }, allow_nil: true
  validates :name, length: { maximum: 100 }, allow_blank: true
  validate :validate_poster_count_within_limit, on: :create

  before_validation :set_default_charset, on: :create

  scope :for_campaign, ->(campaign) { where(campaign: campaign) }
  scope :recent, -> { order(created_at: :desc) }
  scope :with_posters, -> { includes(:posters) }
  scope :with_user, -> { includes(:user) }
  scope :with_campaign, -> { includes(:campaign) }

  # Generate multiple posters for this group
  def generate_posters!(count:, poster_type: "color")
    raise ArgumentError, "Count must be between 1 and #{MAX_POSTERS_PER_GROUP}" unless count.between?(1, MAX_POSTERS_PER_GROUP)

    # No longer block creation based on quota - users can always create posters
    # They just won't earn shards for posters beyond their quota

    transaction do
      count.times do
        posters.create!(
          user: user,
          campaign: campaign,
          poster_type: poster_type,
          verification_status: "pending"
        )
      end
      update!(poster_count: posters.count)
    end

    posters.reload
  end

  # Update cached poster count
  def refresh_poster_count!
    update!(poster_count: posters.count)
  end

  # Check if group has any submitted/verified posters
  def has_submitted_posters?
    if association(:posters).loaded?
      posters.any? { |poster| poster.verification_status != "pending" }
    else
      posters.where.not(verification_status: "pending").exists?
    end
  end

  # Check if all posters in the group are submitted
  def all_submitted?
    if association(:posters).loaded?
      posters.none? { |poster| poster.verification_status == "pending" }
    else
      posters.where(verification_status: "pending").empty?
    end
  end

  # Check if any poster has been verified successfully
  def has_verified_posters?
    if association(:posters).loaded?
      posters.any? { |poster| poster.verification_status == "success" }
    else
      posters.where(verification_status: "success").exists?
    end
  end

  # Get submission status summary - single query instead of 6 separate queries
  def submission_summary
    status_counts = if association(:posters).loaded?
      posters.each_with_object(Hash.new(0)) do |poster, counts|
        counts[poster.verification_status.to_s] += 1
      end
    else
      posters.group(:verification_status).count
    end

    {
      total: status_counts.values.sum,
      pending: status_counts["pending"] || 0,
      in_review: status_counts["in_review"] || 0,
      success: status_counts["success"] || 0,
      rejected: status_counts["rejected"] || 0,
      digital: status_counts["digital"] || 0
    }
  end

  # Custom error class for quota exceeded
  class QuotaExceededError < StandardError; end

  private

  def set_default_charset
    self.charset ||= "alphanumeric"
  end

  def validate_poster_count_within_limit
    # This validation runs on create - actual poster count validated in generate_posters!
    true
  end
end
