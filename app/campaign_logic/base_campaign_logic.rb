# frozen_string_literal: true

# Base class for campaign-specific logic.
# Each campaign can have its own logic class that inherits from this.
#
# Subclasses can override methods to customize:
# - URL generation (referral_base_url, referral_url_for)
# - Asset paths (logo_path, background_pattern_url)
# - Airtable integration (airtable_field_mappings)
# - Shard calculations (calculate_referral_shards, calculate_poster_shards)
# - Validation logic (validate_referral)
#
# @example Creating a campaign-specific logic class
#   class MyCampaignLogic < BaseCampaignLogic
#     def referral_base_url
#       "https://my-campaign.example.com"
#     end
#   end
#
class BaseCampaignLogic
  # Default domain for campaign URLs when no custom base_url is set
  DEFAULT_DOMAIN = "hack.club"

  # Default URL scheme for generated URLs
  DEFAULT_SCHEME = "https"

  # Default referral query parameter name
  REFERRAL_PARAM = "ref"

  attr_reader :campaign

  def initialize(campaign)
    @campaign = campaign
  end

  # Base URL for referral links.
  #
  # Resolution priority:
  #   1. campaign.base_url (if set)
  #   2. subdomain.hack.club (if subdomain present)
  #   3. slug.hack.club (fallback)
  #
  # @return [String] the base URL for referral links
  # @note Override in subclasses for campaign-specific domains
  def referral_base_url
    return campaign.base_url if campaign.base_url.present?

    subdomain = campaign.subdomain.presence || campaign.slug
    build_campaign_url(subdomain)
  end

  # Generate referral URL with the given code.
  #
  # @param code [String] the referral code to include in the URL
  # @return [String] the complete referral URL
  # @note Override in subclasses for custom URL format
  def referral_url_for(code)
    "#{referral_base_url}/?#{REFERRAL_PARAM}=#{code}"
  end

  # Get the poster template path for a given variant.
  #
  # @param variant [String, Symbol] the poster variant name
  # @return [String, nil] the template path or nil if not found
  # @note Override in subclasses for custom poster generation logic
  def poster_template_for(variant)
    campaign.poster_templates&.[](variant.to_s)
  end

  # Get QR code positioning configuration for a poster variant.
  #
  # @param variant [String, Symbol] the poster variant name
  # @return [Hash] the QR code configuration (empty hash if not found)
  # @note Override in subclasses for custom QR code positioning
  def poster_qr_config_for(variant)
    campaign.poster_qr_coordinates&.[](variant.to_s) || {}
  end

  # Get the Airtable field mappings for this campaign.
  #
  # @return [Hash] mapping of internal field names to Airtable column names
  # @note Override in subclasses for custom Airtable field mappings
  def airtable_field_mappings
    campaign.airtable_field_mappings.presence || default_airtable_mappings
  end

  # Validate a referral for this campaign.
  #
  # @param referral [Referral] the referral to validate
  # @return [Boolean] true if valid, false otherwise
  # @note Override in subclasses for custom validation logic
  def validate_referral(referral)
    true
  end

  # Calculate the number of shards earned for a referral.
  #
  # @param referral [Referral] the referral to calculate shards for
  # @return [Integer] the number of shards to award
  # @note Override in subclasses for custom shard calculation
  def calculate_referral_shards(referral)
    campaign.referral_shards
  end

  # Calculate the number of shards earned for a poster.
  #
  # @param poster [Poster] the poster to calculate shards for
  # @return [Integer] the number of shards to award
  # @note Override in subclasses for custom poster shard calculation
  def calculate_poster_shards(poster)
    campaign.poster_shards
  end

  # Get the CSS class for the campaign's theme.
  #
  # @return [String] the CSS theme class name
  # @note Override in subclasses to add custom CSS class for the campaign
  def css_theme_class
    "theme-#{campaign.slug}"
  end

  # Get the URL for the campaign's background pattern.
  #
  # @return [String, nil] the background pattern URL or nil if none
  # @note Override in subclasses for custom background pattern
  def background_pattern_url
    nil
  end

  # Get the path to the campaign's logo asset.
  #
  # @return [String] the logo asset path
  # @note Override in subclasses for custom logo path
  def logo_path
    "#{campaign.slug}/logo.svg"
  end

  protected

  # Build a campaign URL from a subdomain.
  #
  # @param subdomain [String] the subdomain to use
  # @return [String] the complete URL
  def build_campaign_url(subdomain)
    "#{DEFAULT_SCHEME}://#{subdomain}.#{DEFAULT_DOMAIN}"
  end

  private

  def default_airtable_mappings
    {
      "email" => "Email",
      "hours" => "Hours",
      "idv_status" => "IDV Status",
      "projects_shipped" => "Projects Shipped"
    }
  end

  class << self
    # Factory method to get the appropriate logic class for a campaign.
    #
    # Attempts to find a class named "#{CampaignSlug}CampaignLogic" and
    # instantiate it. Falls back to BaseCampaignLogic if no matching
    # class is found.
    #
    # @param campaign [Campaign, nil] the campaign to get logic for
    # @return [BaseCampaignLogic] the campaign logic instance
    #
    # @example
    #   logic = BaseCampaignLogic.for(campaign)
    #   url = logic.referral_url_for("CODE123")
    def for(campaign)
      return new(nil) unless campaign

      return new(campaign) unless campaign.slug

      logic_class_name = "#{campaign.slug.camelize}CampaignLogic"
      logic_class = logic_class_name.safe_constantize

      (logic_class || BaseCampaignLogic).new(campaign)
    end
  end
end
