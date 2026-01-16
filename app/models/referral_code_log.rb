# frozen_string_literal: true

class ReferralCodeLog < ApplicationRecord
  include Geocodable

  validates :referral_code, presence: true
  validates :ip_address, presence: true

  scope :for_code, ->(code) { where(referral_code: code) }
  scope :recent, -> { order(created_at: :desc) }

  after_create_commit :geocode_later

  private

  def geocode_later
    GeocodeIpJob.perform_later(self.class.name, id)
  end
end
