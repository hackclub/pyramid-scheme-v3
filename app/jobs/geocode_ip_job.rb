# frozen_string_literal: true

class GeocodeIpJob < ApplicationJob
  queue_as :default

  GEOCODER_API_URL = "https://geocoder.hackclub.com/v1/geoip"
  PRIVATE_IP_RANGES = [
    IPAddr.new("10.0.0.0/8"),
    IPAddr.new("172.16.0.0/12"),
    IPAddr.new("192.168.0.0/16"),
    IPAddr.new("127.0.0.0/8"),
    IPAddr.new("169.254.0.0/16"),
    IPAddr.new("::1/128"),
    IPAddr.new("fc00::/7"),
    IPAddr.new("fe80::/10")
  ].freeze

  # Whitelist of allowed models to prevent arbitrary code execution via constantize
  ALLOWED_MODELS = %w[ReferralCodeLog LoginLog User PosterScan].freeze

  def perform(model_class, record_id)
    unless ALLOWED_MODELS.include?(model_class.to_s)
      Rails.logger.error("[GeocodeIpJob] Invalid model_class: #{model_class}")
      return
    end
    record = model_class.constantize.find_by(id: record_id)
    return unless record
    return if record.geocoded_at.present?

    # Handle different IP column names for different models
    ip_address = record.respond_to?(:last_ip_address) ? record.last_ip_address : record.ip_address
    return mark_as_geocoded(record) if private_ip?(ip_address)

    geo_data = fetch_geocoding_data(ip_address)
    return mark_as_geocoded(record) unless geo_data

    # Build update hash with only attributes that exist on this model
    update_attrs = {
      latitude: geo_data["lat"],
      longitude: geo_data["lng"],
      city: geo_data["city"],
      region: geo_data["region"],
      country_name: geo_data["country_name"],
      country_code: geo_data["country_code"],
      geocoded_at: Time.current
    }

    # Only include optional attributes if the model has them
    update_attrs[:postal_code] = geo_data["postal_code"] if record.respond_to?(:postal_code=)
    update_attrs[:timezone] = geo_data["timezone"] if record.respond_to?(:timezone=)
    update_attrs[:org] = geo_data["org"] if record.respond_to?(:org=)

    record.update!(update_attrs)
  rescue => e
    Rails.logger.error("[GeocodeIpJob] Failed to geocode #{model_class}##{record_id}: #{e.message}")
  end

  private

  def private_ip?(ip_string)
    return true if ip_string.blank? || ip_string == "unknown"

    ip = IPAddr.new(ip_string)
    PRIVATE_IP_RANGES.any? { |range| range.include?(ip) }
  rescue IPAddr::InvalidAddressError
    true
  end

  def mark_as_geocoded(record)
    record.update!(geocoded_at: Time.current)
  end

  def fetch_geocoding_data(ip_address)
    api_key = ENV["GEOCODER_API_KEY"]
    return nil unless api_key.present?

    uri = URI("#{GEOCODER_API_URL}?ip=#{ip_address}&key=#{api_key}")
    response = Net::HTTP.get_response(uri)

    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue => e
    Rails.logger.error("[GeocodeIpJob] API request failed for #{ip_address}: #{e.message}")
    nil
  end
end
