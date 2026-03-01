# frozen_string_literal: true

# Tracks all referral codes ever used by a user.
# When a user changes their custom referral code, the old one is recorded here.
# This prevents other users from claiming old codes and stealing referrals.
class ReferralCodeHistory < ApplicationRecord
  belongs_to :user

  validates :code, presence: true
  validates :code, uniqueness: { scope: :user_id, case_sensitive: false }
  validates :code_type, presence: true, inclusion: { in: %w[custom standard] }

  scope :active, -> { where(expired_at: nil).or(where("expired_at > ?", Time.current)) }
  scope :for_code, ->(code) { where("LOWER(code) = ?", code.to_s.downcase) }

  # Check if a code was ever used by any user
  def self.code_previously_used?(code)
    where("LOWER(code) = ?", code.to_s.downcase).exists?
  end

  # Find the user who previously owned a code
  def self.find_original_owner(code)
    record = where("LOWER(code) = ?", code.to_s.downcase).order(created_at: :desc).first
    record&.user
  end
end
