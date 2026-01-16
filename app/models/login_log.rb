# frozen_string_literal: true

class LoginLog < ApplicationRecord
  include Geocodable

  belongs_to :user, inverse_of: :login_logs

  validates :ip_address, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :with_user, -> { includes(:user) }
  scope :today, -> { where(created_at: Time.current.beginning_of_day..Time.current.end_of_day) }
  scope :this_week, -> { where(created_at: Time.current.beginning_of_week..Time.current.end_of_week) }

  after_create_commit :geocode_later

  private

  def geocode_later
    GeocodeIpJob.perform_later(self.class.name, id)
  end
end
