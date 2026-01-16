# frozen_string_literal: true

class Poster < ApplicationRecord
  belongs_to :user, optional: true, inverse_of: :posters
  belongs_to :campaign, optional: true, inverse_of: :posters
  belongs_to :verified_by, polymorphic: true, optional: true
  belongs_to :poster_group, optional: true, counter_cache: :poster_count, inverse_of: :posters
  has_many :poster_scans, dependent: :destroy, inverse_of: :poster

  has_one_attached :proof_image do |attachable|
    attachable.variant :thumb, resize_to_limit: [ 300, 300 ]
  end

  has_many_attached :supporting_evidence

  validates :proof_image,
    content_type: { in: [ "image/png", "image/jpeg", "image/jpg", "image/heic", "image/heif", "image/webp" ],
                    message: "must be a valid image format" },
    size: { less_than: 10.megabytes, message: "must be less than 10MB" },
    if: -> { proof_image.attached? }

  validates :supporting_evidence,
    content_type: { in: [ "image/png", "image/jpeg", "image/jpg", "image/heic", "image/heif", "image/webp", "application/pdf", "video/mp4", "video/quicktime" ],
                    message: "must be a valid image, PDF, or video format" },
    size: { less_than: 50.megabytes, message: "must be less than 50MB per file" },
    if: -> { supporting_evidence.attached? }

  validates :qr_code_token, uniqueness: true, allow_nil: true
  validates :referral_code, uniqueness: true, allow_nil: true
  validates :qr_code_token, :referral_code, presence: true, on: :create
  validates :verification_status, inclusion: { in: %w[pending in_review success on_hold rejected digital] }, allow_nil: true
  validates :poster_type, inclusion: { in: %w[color bw printer_efficient] }, allow_nil: true
  validate :location_required_for_proof_submission, on: :update
  validate :location_immutable_after_submission, on: :update

  scope :pending, -> { where(verification_status: "pending") }
  scope :in_review, -> { where(verification_status: "in_review") }
  scope :success, -> { where(verification_status: "success") }
  scope :verified, -> { where(verification_status: "success") } # Alias for backward compatibility
  scope :on_hold, -> { where(verification_status: "on_hold") }
  scope :rejected, -> { where(verification_status: "rejected") }
  scope :digital, -> { where(verification_status: "digital") }
  scope :for_campaign, ->(campaign) { where(campaign: campaign) }
  scope :in_group, -> { where.not(poster_group_id: nil) }
  scope :standalone, -> { where(poster_group_id: nil) }
  scope :recent, -> { order(created_at: :desc) }
  scope :created_this_week, -> { where(created_at: Time.current.beginning_of_week..Time.current.end_of_week) }
  scope :with_user, -> { includes(:user) }
  scope :with_campaign, -> { includes(:campaign) }
  scope :with_associations, -> { includes(:user, :campaign, :poster_group) }
  scope :with_proof, -> { includes(proof_image_attachment: :blob) }

  before_validation :generate_qr_code_token, on: :create
  before_validation :generate_referral_code, on: :create
  before_validation :set_default_verification_status, on: :create
  before_validation :set_default_poster_type, on: :create

  # Check if poster is part of a group
  def in_group?
    poster_group_id.present?
  end

  # Check if location can be edited (only while pending)
  def location_editable?
    verification_status == "pending"
  end

  def verify!(verified_by_user)
    return if verification_status == "success"
    raise ActiveRecord::RecordInvalid, "Cannot verify poster: user or campaign has been deleted" if user.nil? || campaign.nil?

    transaction do
      update!(
        verification_status: "success",
        verified_at: Time.current,
        verified_by: verified_by_user
      )
      award_shards_to_user
      update_user_poster_count
      award_emblem
    end
  end

  def mark_in_review!
    update!(verification_status: "in_review")
  end

  def mark_on_hold!(reason = nil)
    update!(
      verification_status: "on_hold",
      metadata: (metadata || {}).merge(hold_reason: reason)
    )
  end

  def reject!(reason, rejected_by_user)
    update!(
      verification_status: "rejected",
      rejection_reason: reason,
      verified_by: rejected_by_user
    )
  end

  def mark_digital!(verified_by_user)
    return if verification_status == "digital"

    unless user.present? && campaign.present?
      errors.add(:base, "Cannot mark as digital: user or campaign has been deleted")
      raise ActiveRecord::RecordInvalid, self
    end

    unless can_mark_digital?
      errors.add(:base, "Cannot mark as digital: poster has proof or is not pending")
      raise ActiveRecord::RecordInvalid, self
    end

    transaction do
      update!(
        verification_status: "digital",
        verified_at: Time.current,
        verified_by: verified_by_user
      )
    end
  end

  def can_mark_digital?
    verification_status == "pending"
  end

  # Called by PosterAutoVerificationService after successful auto-verification
  def complete_auto_verification!
    transaction do
      update!(
        verification_status: "success",
        verified_at: Time.current,
        verified_by: nil,
        metadata: (metadata || {}).merge(auto_verified: true)
      )
      award_shards_to_user
      update_user_poster_count
      award_emblem
    end
  end

  def request_resubmission!(reason, requested_by_user)
    update!(
      verification_status: "pending",
      metadata: (metadata || {}).merge(
        resubmission_requested: true,
        resubmission_reason: reason,
        resubmission_requested_at: Time.current.iso8601
      ),
      verified_by: requested_by_user
    )
    # Clear existing proof so user can upload new one
    proof_image.purge if proof_image.attached?
  end

  def resubmission_requested?
    metadata&.dig("resubmission_requested") == true
  end

  def resubmission_reason
    metadata&.dig("resubmission_reason")
  end

  def qr_code_url
    "#{Pyramid.base_url}/p/#{qr_code_token}"
  end

  # Generate the referral URL for this poster's QR code
  # Uses the campaign's subdomain on hack.club domain
  # IMPORTANT: This URL is embedded in printed posters - changes break existing posters!
  def referral_url
    return nil unless campaign.present?

    # Use campaign logic for URL generation if available
    campaign_logic = BaseCampaignLogic.for(campaign)
    campaign_logic.referral_url_for(referral_code)
  end

  # Returns the number of scans for this poster
  # Uses counter cache column if available, falls back to count for safety
  def scan_count
    if has_attribute?(:poster_scans_count)
      poster_scans_count
    else
      poster_scans.count
    end
  end

  def record_scan!(ip_address: nil, user_agent: nil, country_code: nil, metadata: {})
    poster_scans.create!(
      ip_address: ip_address,
      user_agent: user_agent,
      country_code: country_code,
      metadata: metadata
    )
  end

  private

  def set_default_verification_status
    self.verification_status ||= "pending"
  end

  def set_default_poster_type
    self.poster_type ||= "color"
  end

  # Location is required when submitting proof (transitioning from pending to in_review)
  def location_required_for_proof_submission
    if verification_status_changed? && verification_status_was == "pending" && verification_status == "in_review"
      if location_description.blank?
        errors.add(:location_description, "is required when submitting proof")
      end
    end
  end

  # Location cannot be changed after poster has been submitted (not pending)
  def location_immutable_after_submission
    return if verification_status_was == "pending" # Allow changes while pending
    return if verification_status_was.nil? # New record

    if location_description_changed? || latitude_changed? || longitude_changed?
      errors.add(:base, "Location cannot be changed after proof has been submitted")
    end
  end

  def generate_qr_code_token
    self.qr_code_token ||= loop do
      token = SecureRandom.alphanumeric(12)
      break token unless Poster.exists?(qr_code_token: token)
    end
  end

  def generate_referral_code
    self.referral_code ||= loop do
      code = SecureRandom.alphanumeric(8).upcase
      break code unless Poster.exists?(referral_code: code)
    end
  end

  def award_shards_to_user
    return unless user.present? && campaign.present?

    # Only award shards if user is within their weekly paid poster limit
    # Count successful posters this week (excluding this one which is being verified now)
    successful_posters_this_week = user.posters
      .success
      .where(created_at: Time.current.beginning_of_week..Time.current.end_of_week)
      .where.not(id: id)
      .count

    if successful_posters_this_week < user.weekly_paid_poster_limit
      user.credit_shards!(
        campaign.poster_shards,
        transaction_type: "poster",
        transactable: self,
        description: "Poster verified"
      )
    end
    # If over limit, poster is verified but no shards awarded
  end

  def update_user_poster_count
    return unless user.present?

    user.update!(poster_count: user.posters.success.count)
  end

  def award_emblem
    return unless user.present? && campaign.present?

    UserEmblem.find_or_create_by!(
      user: user,
      campaign: campaign,
      emblem_type: "participant"
    ) do |emblem|
      emblem.earned_at = Time.current
    end
  end
end
