# frozen_string_literal: true

# Campaign-specific logic for Hack Club The Game (HCTG).
#
# HCTG is a scavenger hunt adventure game across Manhattan.
# Participants build projects and compete in person.
#
class HctgCampaignLogic < BaseCampaignLogic
  def referral_base_url
    "https://hctg.hack.club"
  end

  def logo_path
    "hctg/icon.svg"
  end

  # Field mappings for the HCTG Airtable "Pyramid" table
  def airtable_field_mappings
    {
      "email" => "Email",
      "referral_code" => "Referral Code",
      "idv_status" => "IDV Status",
      "hours" => "Hours"
    }
  end
end
