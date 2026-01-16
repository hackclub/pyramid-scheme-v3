# frozen_string_literal: true

require "test_helper"

class CampaignTest < ActiveSupport::TestCase
  setup do
    @flavortown = campaigns(:flavortown)
    @aces = campaigns(:aces)
    @closed = campaigns(:closed_campaign)
  end

  # =============================================================================
  # VALIDATIONS
  # =============================================================================
  test "valid campaign with required attributes" do
    campaign = Campaign.new(
      name: "New Campaign",
      slug: "new-campaign",
      theme: "flavortown",
      status: "open",
      referral_shards: 3,
      poster_shards: 1,
      required_coding_minutes: 60
    )
    assert campaign.valid?
  end

  test "invalid without name" do
    campaign = Campaign.new(slug: "test", theme: "test")
    assert_not campaign.valid?
    assert_includes campaign.errors[:name], "can't be blank"
  end

  test "invalid without slug" do
    campaign = Campaign.new(name: "Test", theme: "test")
    assert_not campaign.valid?
    assert_includes campaign.errors[:slug], "can't be blank"
  end

  test "slug must be unique" do
    duplicate = Campaign.new(
      name: "Duplicate",
      slug: @flavortown.slug,
      theme: "test"
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug], "has already been taken"
  end

  test "slug format only allows lowercase letters, numbers, and hyphens" do
    invalid_slugs = [ "Test Campaign", "test_campaign", "TEST", "test.campaign" ]
    invalid_slugs.each do |slug|
      campaign = Campaign.new(name: "Test", slug: slug, theme: "test")
      assert_not campaign.valid?, "Expected '#{slug}' to be invalid"
      assert_includes campaign.errors[:slug], "only allows lowercase letters, numbers, and hyphens"
    end
  end

  test "valid slug formats" do
    valid_slugs = [ "test", "test-campaign", "test123", "123test" ]
    valid_slugs.each do |slug|
      campaign = Campaign.new(
        name: "Test",
        slug: slug,
        theme: "test",
        referral_shards: 3,
        poster_shards: 1,
        required_coding_minutes: 60
      )
      assert campaign.valid?, "Expected '#{slug}' to be valid: #{campaign.errors.full_messages}"
    end
  end

  # =============================================================================
  # STATUS METHODS
  # =============================================================================
  test "open? returns true for open campaign" do
    assert @flavortown.open?
  end

  test "coming_soon? returns true for coming soon campaign" do
    assert @aces.coming_soon?
  end

  test "closed? returns true for closed campaign" do
    assert @closed.closed?
  end

  # =============================================================================
  # REFERRAL URL GENERATION
  # =============================================================================
  test "referral_base_url uses subdomain when present" do
    campaign = Campaign.new(slug: "test", subdomain: "mysubdomain")
    assert_equal "https://mysubdomain.hack.club", campaign.referral_base_url
  end

  test "referral_base_url uses slug when no subdomain" do
    campaign = Campaign.new(slug: "testslug", subdomain: nil)
    assert_equal "https://testslug.hack.club", campaign.referral_base_url
  end

  test "referral_base_url prefers base_url when set" do
    campaign = Campaign.new(
      slug: "test",
      subdomain: "sub",
      base_url: "https://custom.example.com"
    )
    assert_equal "https://custom.example.com", campaign.referral_base_url
  end

  test "referral_url_for generates correct URL" do
    url = @flavortown.referral_url_for("TESTCODE")
    assert_includes url, "TESTCODE"
    assert_includes url, "?ref="
  end

  # =============================================================================
  # SCOPES
  # =============================================================================
  test "active scope returns only active campaigns" do
    active_campaigns = Campaign.active
    active_campaigns.each do |campaign|
      assert campaign.active?, "Expected campaign '#{campaign.name}' to be active"
    end
  end

  test "open_status scope returns only open campaigns" do
    open_campaigns = Campaign.open_status
    open_campaigns.each do |campaign|
      assert_equal "open", campaign.status
    end
  end

  test "not_closed scope excludes closed campaigns" do
    not_closed = Campaign.not_closed
    not_closed.each do |campaign|
      assert_not_equal "closed", campaign.status
    end
  end

  # =============================================================================
  # AIRTABLE CONFIGURATION
  # =============================================================================
  test "airtable_configured? returns false without base_id" do
    campaign = Campaign.new(airtable_sync_enabled: true, airtable_table_id: "tbl123")
    assert_not campaign.airtable_configured?
  end

  test "airtable_configured? returns true with all config" do
    campaign = Campaign.new(
      airtable_sync_enabled: true,
      airtable_base_id: "app123",
      airtable_table_id: "tbl123"
    )
    assert campaign.airtable_configured?
  end

  test "effective_field_mappings merges default and custom mappings" do
    campaign = Campaign.new(
      airtable_field_mappings: { "custom_field" => "Custom" }
    )
    mappings = campaign.effective_field_mappings

    assert_includes mappings.keys, "email"
    assert_includes mappings.keys, "custom_field"
  end

  # =============================================================================
  # POSTER CONFIGURATION
  # =============================================================================
  test "default_qr_config_for returns coordinates for each variant" do
    %w[color bw printer_efficient].each do |variant|
      config = @flavortown.default_qr_config_for(variant)
      assert config.key?("x"), "Expected x coordinate for #{variant}"
      assert config.key?("y"), "Expected y coordinate for #{variant}"
      assert config.key?("size"), "Expected size for #{variant}"
    end
  end

  # =============================================================================
  # ACCESSIBILITY
  # =============================================================================
  test "accessible_by? returns true for open campaign" do
    user = users(:regular_user)
    assert @flavortown.accessible_by?(user)
  end

  test "accessible_by? returns false for closed campaign" do
    user = users(:regular_user)
    assert_not @closed.accessible_by?(user)
  end

  test "accessible_by? returns true for admin on coming_soon campaign" do
    admin = users(:admin)
    assert @aces.accessible_by?(admin)
  end

  test "accessible_by? returns false for regular user on coming_soon campaign" do
    user = users(:regular_user)
    assert_not @aces.accessible_by?(user)
  end

  # =============================================================================
  # LEADERBOARD
  # =============================================================================
  test "leaderboard_referrals returns users with completed referrals" do
    leaderboard = @flavortown.leaderboard_referrals
    # Verify it's a valid query that can be executed
    assert_kind_of ActiveRecord::Relation, leaderboard
  end

  test "leaderboard_posters returns users with verified posters" do
    leaderboard = @flavortown.leaderboard_posters
    assert_kind_of ActiveRecord::Relation, leaderboard
  end
end
