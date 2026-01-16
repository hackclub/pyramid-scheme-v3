# frozen_string_literal: true

module Shop
  module Regionalizable
    extend ActiveSupport::Concern

    REGIONS = {
      "US" => { name: "United States", countries: [ "US" ] },
      "EU" => { name: "EU", countries: [ "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE" ] },
      "UK" => { name: "United Kingdom", countries: [ "GB" ] },
      "IN" => { name: "India", countries: [ "IN" ] },
      "CA" => { name: "Canada", countries: [ "CA" ] },
      "AU" => { name: "Australia", countries: [ "AU", "NZ" ] },
      "XX" => { name: "Rest of World", countries: [] }
    }.freeze

    REGION_CODES = REGIONS.keys.freeze

    TIMEZONE_TO_REGION = {
      # United States
      "America/New_York" => "US", "America/Chicago" => "US", "America/Denver" => "US",
      "America/Los_Angeles" => "US", "America/Phoenix" => "US", "America/Anchorage" => "US",
      "Pacific/Honolulu" => "US", "America/Detroit" => "US", "America/Indiana/Indianapolis" => "US",
      # Canada
      "America/Toronto" => "CA", "America/Vancouver" => "CA", "America/Edmonton" => "CA",
      "America/Winnipeg" => "CA", "America/Halifax" => "CA", "America/St_Johns" => "CA",
      # United Kingdom
      "Europe/London" => "UK",
      # EU countries
      "Europe/Paris" => "EU", "Europe/Berlin" => "EU", "Europe/Rome" => "EU",
      "Europe/Madrid" => "EU", "Europe/Amsterdam" => "EU", "Europe/Brussels" => "EU",
      "Europe/Vienna" => "EU", "Europe/Stockholm" => "EU", "Europe/Copenhagen" => "EU",
      "Europe/Helsinki" => "EU", "Europe/Warsaw" => "EU", "Europe/Prague" => "EU",
      "Europe/Budapest" => "EU", "Europe/Athens" => "EU", "Europe/Bucharest" => "EU",
      "Europe/Sofia" => "EU", "Europe/Dublin" => "EU", "Europe/Lisbon" => "EU",
      "Europe/Zagreb" => "EU", "Europe/Ljubljana" => "EU", "Europe/Bratislava" => "EU",
      "Europe/Tallinn" => "EU", "Europe/Riga" => "EU", "Europe/Vilnius" => "EU",
      "Europe/Luxembourg" => "EU", "Europe/Malta" => "EU",
      # India
      "Asia/Kolkata" => "IN", "Asia/Calcutta" => "IN",
      # Australia/NZ
      "Australia/Sydney" => "AU", "Australia/Melbourne" => "AU", "Australia/Brisbane" => "AU",
      "Australia/Perth" => "AU", "Australia/Adelaide" => "AU", "Australia/Hobart" => "AU",
      "Pacific/Auckland" => "AU", "Pacific/Fiji" => "AU"
    }.freeze

    # Module-level methods that can be called directly on Shop::Regionalizable
    def self.country_to_region(country_code)
      return "XX" if country_code.blank?

      REGIONS.each do |region_code, config|
        next if region_code == "XX"
        return region_code if config[:countries].include?(country_code.upcase)
      end

      "XX"
    end

    def self.timezone_to_region(timezone)
      return "XX" if timezone.blank?
      TIMEZONE_TO_REGION[timezone] || "XX"
    end

    def self.region_name(region_code)
      REGIONS.dig(region_code.upcase, :name) || "Unknown Region"
    end

    def self.countries_for_region(region_code)
      REGIONS.dig(region_code.upcase, :countries) || []
    end

    class_methods do
      def region_columns
        @region_columns ||= REGION_CODES.flat_map do |code|
          [ "enabled_#{code.downcase}", "price_offset_#{code.downcase}" ]
        end
      end

      def country_to_region(country_code)
        return "XX" if country_code.blank?

        REGIONS.each do |region_code, config|
          next if region_code == "XX"
          return region_code if config[:countries].include?(country_code.upcase)
        end

        "XX"
      end

      def timezone_to_region(timezone)
        return "XX" if timezone.blank?
        TIMEZONE_TO_REGION[timezone] || "XX"
      end

      def region_name(region_code)
        REGIONS.dig(region_code.upcase, :name) || "Unknown Region"
      end

      def countries_for_region(region_code)
        REGIONS.dig(region_code.upcase, :countries) || []
      end
    end

    included do
      # Define scope methods for each region
      REGION_CODES.each do |code|
        column = "enabled_#{code.downcase}".to_sym
        scope :"enabled_in_#{code.downcase}", -> { where(column => true) }
        scope :"disabled_in_#{code.downcase}", -> { where(column => [ false, nil ]) }
      end
    end

    def any_region_enabled?
      REGION_CODES.any? { |code| send("enabled_#{code.downcase}") }
    end

    def enabled_in_region?(region_code)
      return false unless REGION_CODES.include?(region_code.to_s.upcase)

      # If no regions are explicitly enabled, item is available everywhere
      return true unless any_region_enabled?

      region_value = send("enabled_#{region_code.downcase}")

      # If explicitly set for this region, use that value
      return region_value unless region_value.nil?

      # Fall back to XX (Rest of World) if region is not explicitly set
      enabled_xx
    end

    def price_for_region(region_code)
      region_code = region_code.to_s.upcase
      region_code = "XX" unless REGION_CODES.include?(region_code)

      # Get region-specific offset, falling back to XX offset if not set
      region_offset = send("price_offset_#{region_code.downcase}")
      offset = region_offset.present? ? region_offset : (send("price_offset_xx") || 0)

      # Use current_price which accounts for sales
      base_price = respond_to?(:current_price) ? current_price : price_shards
      (base_price + offset).to_i
    end

    def regions_enabled
      REGION_CODES.select { |code| enabled_in_region?(code) }
    end
  end
end
