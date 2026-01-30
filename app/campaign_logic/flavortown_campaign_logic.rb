# frozen_string_literal: true

# Campaign-specific logic for Flavortown.
#
# Flavortown is a standard campaign with custom visual branding
# (striped background pattern and AVIF logo format).
#
class FlavortownCampaignLogic < BaseCampaignLogic
  # Campaign subdomain for URL generation
  SUBDOMAIN = "flavortown"

  def referral_base_url
    build_campaign_url(SUBDOMAIN)
  end

  # Custom field mappings for Flavortown Airtable.
  # Flavortown uses lowercase "ref" instead of "Referral Code".
  #
  # @return [Hash] mapping of internal field names to Airtable column names
  def airtable_field_mappings
    {
      "email" => "email",
      "hours" => "hours",
      "idv_status" => "verification_status",
      "referral_code" => "ref"
    }.freeze
  end

  def background_pattern_url
    "#{SUBDOMAIN}/striped-btn-bg.svg"
  end

  def logo_path
    "#{SUBDOMAIN}/logo.avif"
  end
end
