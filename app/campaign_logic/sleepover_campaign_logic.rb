# frozen_string_literal: true

# Campaign-specific logic for Sleepover.
#
# Sleepover is a coding-hours based campaign with custom branding.
#
class SleepoverCampaignLogic < BaseCampaignLogic
  # Campaign subdomain for URL generation
  SUBDOMAIN = "sleepover"

  def referral_base_url
    build_campaign_url(SUBDOMAIN)
  end

  def background_pattern_url
    "sleepover/bunny-tile.png"
  end

  def logo_path
    "sleepover/sleepover_logo.png"
  end
end
