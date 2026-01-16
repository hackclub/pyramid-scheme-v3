# frozen_string_literal: true

# Handles creation of referrals from session data after user authentication.
# Extracted from SessionsController to improve testability and reduce controller complexity.
class ReferralFromSessionService
  def initialize(referred_user:, referral_code:, referral_type:, campaign:)
    @referred_user = referred_user
    @referral_code = referral_code
    @referral_type = referral_type || "link"
    @campaign = campaign
  end

  # Creates a referral if valid, returns the referral or nil.
  # @return [Referral, nil]
  def call
    return nil unless @referral_code.present?

    Rails.logger.info("Processing referral code: #{@referral_code} for user #{@referred_user.slack_id}")

    referrer = find_referrer
    return nil unless referrer
    return nil if self_referral?(referrer)
    return nil if referral_exists?(referrer)

    create_referral(referrer)
  rescue StandardError => e
    Rails.logger.error("Failed to create referral: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    nil
  end

  private

  def find_referrer
    referrer = User.find_by_any_referral_code(@referral_code)
    referrer ||= User.find_by(slack_id: @referral_code)

    unless referrer
      Rails.logger.warn("Referrer not found for code: #{@referral_code}")
    end

    referrer
  end

  def self_referral?(referrer)
    if referrer.id == @referred_user.id
      Rails.logger.warn("Attempted self-referral for user #{@referred_user.slack_id}")
      true
    else
      false
    end
  end

  def referral_exists?(referrer)
    existing = Referral.find_by(
      referrer: referrer,
      referred_identifier: @referred_user.slack_id,
      campaign: @campaign
    )

    if existing
      Rails.logger.info("Referral already exists: #{existing.id}")
      true
    else
      false
    end
  end

  def create_referral(referrer)
    referral = Referral.create!(
      referrer: referrer,
      referred: @referred_user,
      referred_identifier: @referred_user.slack_id,
      campaign: @campaign,
      referral_type: @referral_type,
      status: :pending,
      tracked_minutes: 0
    )

    Rails.logger.info("Created referral #{referral.id}: #{referrer.slack_id} -> #{@referred_user.slack_id}")
    referral
  end
end
