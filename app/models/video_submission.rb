# frozen_string_literal: true

class VideoSubmission < ApplicationRecord
  belongs_to :user, inverse_of: :video_submissions
  belongs_to :campaign, inverse_of: :video_submissions
  belongs_to :reviewed_by, class_name: "User", optional: true
  belongs_to :virality_checked_by, class_name: "User", optional: true

  has_many_attached :video_files do |attachable|
    attachable.variant :thumb, resize_to_limit: [ 300, 300 ]
  end

  STATUSES = %w[pending on_hold approved rejected].freeze
  VIRALITY_STATUSES = %w[pending completed].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :virality_status, inclusion: { in: VIRALITY_STATUSES }
  validates :shards_awarded, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10 }
  validates :viral_bonus, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 20 }
  validate :has_url_or_files

  validates :video_files,
    content_type: { in: [ "video/mp4", "video/quicktime", "video/webm", "video/x-msvideo", "image/png", "image/jpeg", "image/jpg", "image/gif", "image/webp" ],
                    message: "must be a valid video or image format" },
    size: { less_than: 200.megabytes, message: "total must be less than 200MB" },
    limit: { max: 5, message: "cannot upload more than 5 files" },
    if: -> { video_files.attached? }

  scope :pending, -> { where(status: "pending") }
  scope :on_hold, -> { where(status: "on_hold") }
  scope :approved, -> { where(status: "approved") }
  scope :rejected, -> { where(status: "rejected") }
  scope :for_campaign, ->(campaign) { where(campaign: campaign) }
  scope :recent, -> { order(created_at: :desc) }
  scope :virality_pending, -> { where(virality_status: "pending", status: "approved") }
  scope :with_user, -> { includes(:user) }
  scope :with_campaign, -> { includes(:campaign) }
  scope :with_files, -> { includes(video_files_attachments: :blob) }
  scope :with_associations, -> { includes(:user, :campaign, video_files_attachments: :blob) }

  def pending?
    status == "pending"
  end

  def on_hold?
    status == "on_hold"
  end

  def approved?
    status == "approved"
  end

  def rejected?
    status == "rejected"
  end

  def virality_pending?
    virality_status == "pending"
  end

  def virality_completed?
    virality_status == "completed"
  end

  def can_delete?
    pending?
  end

  def can_check_virality?
    approved? && virality_pending?
  end

  def total_shards
    shards_awarded + viral_bonus
  end

  def approve!(reviewer, shards:)
    raise ArgumentError, "Shards must be between 1 and 10" unless shards.between?(1, 10)

    transaction do
      update!(
        status: "approved",
        shards_awarded: shards,
        reviewed_at: Time.current,
        reviewed_by: reviewer
      )
      award_shards!(shards, "video")
    end
  end

  def hold!(reviewer, notes: nil)
    update!(
      status: "on_hold",
      reviewer_notes: notes,
      reviewed_at: Time.current,
      reviewed_by: reviewer
    )
  end

  def reject!(reviewer, notes: nil)
    update!(
      status: "rejected",
      reviewer_notes: notes,
      reviewed_at: Time.current,
      reviewed_by: reviewer
    )
  end

  def complete_virality_check!(reviewer, is_viral:, bonus: 0)
    raise ArgumentError, "Bonus must be between 0 and 20" unless bonus.between?(0, 20)
    raise ArgumentError, "Must be approved to check virality" unless approved?

    transaction do
      update!(
        virality_status: "completed",
        is_viral: is_viral,
        viral_bonus: bonus,
        virality_checked_at: Time.current,
        virality_checked_by: reviewer
      )
      award_shards!(bonus, "video_viral_bonus") if bonus.positive?
    end
  end

  private

  def has_url_or_files
    if video_url.blank? && !video_files.attached?
      errors.add(:base, "You must provide either a video URL or upload files")
    end
  end

  def award_shards!(amount, transaction_type)
    return if amount <= 0

    user.credit_shards!(
      amount,
      transaction_type: transaction_type,
      transactable: self,
      description: transaction_type == "video" ? "Video submission approved" : "Video viral bonus"
    )
  end
end
