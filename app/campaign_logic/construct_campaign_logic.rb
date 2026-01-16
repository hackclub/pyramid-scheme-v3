# frozen_string_literal: true

# Campaign-specific logic for Construct hardware event.
#
# This campaign tracks Projects and Ships instead of coding hours.
# Completion is based on verified ship count >= 1 (not hours).
# All participants are considered ID verified.
#
class ConstructCampaignLogic < BaseCampaignLogic
  # Campaign subdomain for URL generation
  SUBDOMAIN = "construct"

  # Minimum number of ships required for referral completion
  MINIMUM_SHIPS_FOR_COMPLETION = 1

  def referral_base_url
    build_campaign_url(SUBDOMAIN)
  end

  # Custom field mappings for Construct Airtable.
  # Table "Pyramid": Name, Email, User ID, Project Count, Verified Shipped Count, Referral Code.
  #
  # @return [Hash] mapping of internal field names to Airtable column names
  def airtable_field_mappings
    {
      "email" => "Email",
      "name" => "Name",
      "referral_code" => "Referral Code",
      "projects_count" => "Project Count",
      "ships_count" => "Verified Shipped Count"
    }.freeze
  end

  # Check if a referral is complete for Construct.
  # Completion is based on ships, not hours - everyone is ID verified.
  #
  # @param referral [Referral] the referral to check
  # @return [Boolean] true if the referral has enough ships
  def referral_complete?(referral)
    ships_count_from_referral(referral) >= MINIMUM_SHIPS_FOR_COMPLETION
  end

  # Get a human-readable status label for a referral.
  #
  # @param referral [Referral] the referral to get status for
  # @return [String] the status label
  def referral_status_label(referral)
    return "Successful" if referral.completed?
    return "Ready to Complete" if has_minimum_ships?(referral)

    "Waiting for Ship"
  end

  # Get detailed status information for display.
  #
  # @param referral [Referral] the referral to get details for
  # @return [Hash] status details including ship and project counts
  def referral_status_details(referral)
    ships = ships_count_from_referral(referral)
    projects = projects_count_from_referral(referral)

    {
      ships_count: ships,
      projects_count: projects,
      waiting_for_ship: ships < MINIMUM_SHIPS_FOR_COMPLETION
    }
  end

  def logo_path
    "#{SUBDOMAIN}/logo-nobg.png"
  end

  def background_pattern_url
    nil
  end

  private

  # Extract ships count from referral metadata.
  #
  # @param referral [Referral] the referral to extract from
  # @return [Integer] the ships count (0 if not found)
  def ships_count_from_referral(referral)
    referral.metadata&.dig("ships_count").to_i
  end

  # Extract projects count from referral metadata.
  #
  # @param referral [Referral] the referral to extract from
  # @return [Integer] the projects count (0 if not found)
  def projects_count_from_referral(referral)
    referral.metadata&.dig("projects_count").to_i
  end

  # Check if referral has minimum ships for completion.
  #
  # @param referral [Referral] the referral to check
  # @return [Boolean] true if has minimum ships
  def has_minimum_ships?(referral)
    ships_count_from_referral(referral) >= MINIMUM_SHIPS_FOR_COMPLETION
  end
end
