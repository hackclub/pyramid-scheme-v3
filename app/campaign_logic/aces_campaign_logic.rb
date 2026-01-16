# frozen_string_literal: true

# Campaign-specific logic for Aces.
#
# Aces is a coding-hours based campaign with custom Airtable field mappings.
# The "User data" table includes: Email, Hours, Projects Shipped, IDV Status, Referral Code.
#
class AcesCampaignLogic < BaseCampaignLogic
  # Campaign subdomain for URL generation
  SUBDOMAIN = "aces"

  def referral_base_url
    build_campaign_url(SUBDOMAIN)
  end

  # Custom field mappings for Aces Airtable.
  # Table: "User data" - has Email, Hours, Projects Shipped, IDV Status, Referral Code (no Name).
  #
  # @return [Hash] mapping of internal field names to Airtable column names
  def airtable_field_mappings
    {
      "email" => "Email",
      "hours" => "Hours",
      "idv_status" => "IDV Status",
      "referral_code" => "Referral Code",
      "projects_shipped" => "Projects Shipped"
    }.freeze
  end

  def logo_path
    "#{SUBDOMAIN}/logo.svg"
  end
end
