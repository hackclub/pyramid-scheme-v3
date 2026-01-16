# frozen_string_literal: true

module Geocodable
  extend ActiveSupport::Concern

  included do
    scope :geocoded, -> { where.not(geocoded_at: nil) }
    scope :not_geocoded, -> { where(geocoded_at: nil) }
    scope :by_country, ->(code) { where(country_code: code) }
  end

  def geocoded?
    geocoded_at.present?
  end

  def location_display
    [ city, region, country_name ].compact.reject(&:blank?).join(", ")
  end
end
