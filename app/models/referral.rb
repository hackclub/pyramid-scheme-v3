# frozen_string_literal: true

class Referral < ApplicationRecord
  enum :status, { pending: 0, id_verified: 1, completed: 2 }

  belongs_to :referrer, class_name: "User", inverse_of: :referrals_given
  belongs_to :referred, class_name: "User", optional: true, inverse_of: :referrals_received
  belongs_to :campaign, inverse_of: :referrals

  validates :referred_identifier, presence: true
  validates :referred_identifier, uniqueness: { scope: :referrer_id, message: "has already been referred by you" }
  validates :status, presence: true
  validates :tracked_minutes, numericality: { greater_than_or_equal_to: 0 }
  validates :referral_type, presence: true, inclusion: { in: %w[link poster] }

  scope :for_campaign, ->(campaign) { where(campaign: campaign) }
  scope :by_referrer, ->(user) { where(referrer: user) }
  scope :from_links, -> { where(referral_type: "link") }
  scope :from_posters, -> { where(referral_type: "poster") }
  scope :recent, -> { order(created_at: :desc) }
  scope :completed_this_week, -> { completed.where(completed_at: Time.current.beginning_of_week..Time.current.end_of_week) }
  scope :with_referrer, -> { includes(:referrer) }
  scope :with_associations, -> { includes(:referrer, :referred, :campaign) }

  after_save :check_completion_and_award_shards, if: :saved_change_to_status?

  def pending_status
    return nil unless pending?
    metadata&.dig("verification_status")
  end

  def pending_status_label
    return nil unless pending?

    case pending_status&.downcase
    when "needs_submission"
      "Needs ID"
    when "submitted", "in_review"
      "ID Reviewing"
    when "rejected"
      "ID Rejected"
    else
      "Pending"
    end
  end

  def verify_identity!
    return if id_verified? || completed?

    update!(status: :id_verified, verified_at: Time.current)
  end

  def complete!
    return if completed?
    return unless id_verified?
    return unless tracked_minutes >= campaign.required_coding_minutes

    transaction do
      # Set flag to prevent callback from awarding shards
      @completing_via_method = true
      update!(status: :completed, completed_at: Time.current)
      award_shards_to_referrer
      update_referrer_count
      award_emblem
    ensure
      @completing_via_method = false
    end
  end

  def update_tracked_time!(minutes)
    update!(tracked_minutes: minutes)
    complete! if id_verified? && minutes >= campaign.required_coding_minutes
  end

  def progress_percentage
    return 100 if completed?
    return 0 if campaign.required_coding_minutes.zero?

    [ (tracked_minutes.to_f / campaign.required_coding_minutes * 100).round, 100 ].min
  end

  private

  def check_completion_and_award_shards
    # Don't award if we're being called from within complete! method
    return if @completing_via_method
    return unless completed? && status_before_last_save != "completed"

    award_shards_to_referrer unless referrer.shard_transactions.exists?(transactable: self)
    update_referrer_count
    award_emblem
    send_completion_notifications
  end

  def award_shards_to_referrer
    referrer.credit_shards!(
      campaign.referral_shards,
      transaction_type: "referral",
      transactable: self,
      description: "Referral completed for #{referred_identifier}"
    )
  end

  def send_completion_notifications
    # Notify the referrer they earned shards
    SlackNotificationService.new.notify_referral_completed(
      user: referrer,
      referral: self,
      shards: campaign.referral_shards
    )

    # Notify admin of completed referral
    SlackNotificationService.new.notify_admin_new_referral(referral: self)
  rescue Faraday::Error, JSON::ParserError => e
    # Notification failures are non-critical - log but don't fail the transaction
    Rails.logger.error "[Referral##{id}] Failed to send completion notifications: #{e.class} - #{e.message}"
  end

  def update_referrer_count
    referrer.update!(referral_count: referrer.referrals_given.completed.count)
  end

  def award_emblem
    UserEmblem.find_or_create_by!(
      user: referrer,
      campaign: campaign,
      emblem_type: "participant"
    ) do |emblem|
      emblem.earned_at = Time.current
    end
  end
end
