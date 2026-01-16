# frozen_string_literal: true

class PosterScan < ApplicationRecord
  include Geocodable

  belongs_to :poster, inverse_of: :poster_scans, counter_cache: :poster_scans_count

  scope :recent, -> { order(created_at: :desc) }
  scope :by_country, ->(country_code) { where(country_code: country_code) if country_code.present? }
  scope :with_poster, -> { includes(:poster) }
  scope :with_poster_user, -> { includes(poster: :user) }

  after_create_commit :geocode_later

  def self.country_stats
    group(:country_code).count
  end

  private

  def geocode_later
    GeocodeIpJob.perform_later(self.class.name, id)
  end
end
