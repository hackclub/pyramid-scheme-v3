# frozen_string_literal: true

require "test_helper"

class BaseCampaignLogicTest < ActiveSupport::TestCase
  setup do
    @flavortown = campaigns(:flavortown)
    @aces = campaigns(:aces)
    @construct = campaigns(:construct)
  end

  # =============================================================================
  # FACTORY METHOD
  # =============================================================================
  test "for returns appropriate logic class for flavortown" do
    logic = BaseCampaignLogic.for(@flavortown)
    assert_instance_of FlavortownCampaignLogic, logic
  end

  test "for returns appropriate logic class for aces" do
    logic = BaseCampaignLogic.for(@aces)
    assert_instance_of AcesCampaignLogic, logic
  end

  test "for returns appropriate logic class for construct" do
    logic = BaseCampaignLogic.for(@construct)
    assert_instance_of ConstructCampaignLogic, logic
  end

  test "for returns base class for unknown campaign" do
    unknown = Campaign.new(slug: "unknown-campaign", name: "Unknown")
    logic = BaseCampaignLogic.for(unknown)
    assert_instance_of BaseCampaignLogic, logic
  end

  test "for returns base class for nil campaign" do
    logic = BaseCampaignLogic.for(nil)
    assert_instance_of BaseCampaignLogic, logic
  end

  # =============================================================================
  # REFERRAL URL GENERATION
  # =============================================================================
  test "referral_base_url uses subdomain when present" do
    logic = BaseCampaignLogic.for(@flavortown)
    assert_equal "https://flavortown.hack.club", logic.referral_base_url
  end

  test "referral_base_url uses slug when no subdomain" do
    campaign = Campaign.new(slug: "test-campaign", subdomain: nil)
    logic = BaseCampaignLogic.new(campaign)
    assert_equal "https://test-campaign.hack.club", logic.referral_base_url
  end

  test "referral_base_url uses base_url when set" do
    campaign = Campaign.new(
      slug: "custom",
      subdomain: "sub",
      base_url: "https://custom.example.com"
    )
    logic = BaseCampaignLogic.new(campaign)
    assert_equal "https://custom.example.com", logic.referral_base_url
  end

  test "referral_url_for generates correct URL" do
    logic = BaseCampaignLogic.for(@flavortown)
    url = logic.referral_url_for("TESTCODE")

    assert_equal "https://flavortown.hack.club/?ref=TESTCODE", url
  end

  # =============================================================================
  # FLAVORTOWN SPECIFIC
  # =============================================================================
  test "flavortown logic uses correct base URL" do
    logic = BaseCampaignLogic.for(@flavortown)
    assert_equal "https://flavortown.hack.club", logic.referral_base_url
  end

  test "flavortown logo path is correct" do
    logic = BaseCampaignLogic.for(@flavortown)
    assert_equal "flavortown/logo.avif", logic.logo_path
  end

  # =============================================================================
  # ACES SPECIFIC
  # =============================================================================
  test "aces logic uses correct base URL" do
    logic = BaseCampaignLogic.for(@aces)
    assert_equal "https://aces.hack.club", logic.referral_base_url
  end

  # =============================================================================
  # CONSTRUCT SPECIFIC
  # =============================================================================
  test "construct logic uses correct base URL" do
    logic = BaseCampaignLogic.for(@construct)
    assert_equal "https://construct.hack.club", logic.referral_base_url
  end

  test "construct has custom airtable_field_mappings" do
    logic = BaseCampaignLogic.for(@construct)
    mappings = logic.airtable_field_mappings

    assert_includes mappings.keys, "ships_count"
    assert_includes mappings.keys, "projects_count"
  end

  # =============================================================================
  # SHARD CALCULATION
  # =============================================================================
  test "calculate_referral_shards returns campaign value" do
    logic = BaseCampaignLogic.for(@flavortown)
    assert_equal @flavortown.referral_shards, logic.calculate_referral_shards(nil)
  end

  test "calculate_poster_shards returns campaign value" do
    logic = BaseCampaignLogic.for(@flavortown)
    assert_equal @flavortown.poster_shards, logic.calculate_poster_shards(nil)
  end

  # =============================================================================
  # THEME
  # =============================================================================
  test "css_theme_class returns correct class" do
    logic = BaseCampaignLogic.for(@flavortown)
    assert_equal "theme-flavortown", logic.css_theme_class
  end
end
