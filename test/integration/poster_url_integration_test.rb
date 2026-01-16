# frozen_string_literal: true

require "test_helper"

class PosterUrlIntegrationTest < ActiveSupport::TestCase
  # =============================================================================
  # CRITICAL REGRESSION TESTS
  # These tests ensure poster URLs are generated correctly for all campaigns
  # Regression: The URL was incorrectly hardcoded to flavortown.hackclub.com
  # instead of using the campaign's actual subdomain on hack.club
  # =============================================================================

  test "poster URL uses campaign subdomain on hack.club domain" do
    Campaign.active.each do |campaign|
      user = create_user
      poster = create_poster(user: user, campaign: campaign)

      url = poster.referral_url

      # URL should use hack.club domain
      assert_match(/\.hack\.club/, url,
        "Campaign #{campaign.slug}: URL should use hack.club domain")

      # URL should NOT use hackclub.com domain
      assert_no_match(/hackclub\.com/, url,
        "Campaign #{campaign.slug}: URL should NOT use hackclub.com domain")

      # URL should include the referral code
      assert_includes(url, poster.referral_code,
        "Campaign #{campaign.slug}: URL should include referral code")
    end
  end

  test "poster URL matches campaign logic referral_url_for" do
    Campaign.active.each do |campaign|
      user = create_user
      poster = create_poster(user: user, campaign: campaign)

      # Get URL from poster
      poster_url = poster.referral_url

      # Get URL from campaign logic
      campaign_logic = BaseCampaignLogic.for(campaign)
      expected_url = campaign_logic.referral_url_for(poster.referral_code)

      assert_equal expected_url, poster_url,
        "Campaign #{campaign.slug}: Poster URL should match campaign logic URL"
    end
  end

  test "flavortown uses flavortown.hack.club" do
    campaign = campaigns(:flavortown)
    user = create_user
    poster = create_poster(user: user, campaign: campaign)

    assert_equal "https://flavortown.hack.club/?ref=#{poster.referral_code}",
      poster.referral_url
  end

  test "aces uses aces.hack.club" do
    campaign = campaigns(:aces)
    user = create_user
    poster = create_poster(user: user, campaign: campaign)

    assert_equal "https://aces.hack.club/?ref=#{poster.referral_code}",
      poster.referral_url
  end

  test "construct uses construct.hack.club" do
    campaign = campaigns(:construct)
    user = create_user
    poster = create_poster(user: user, campaign: campaign)

    assert_equal "https://construct.hack.club/?ref=#{poster.referral_code}",
      poster.referral_url
  end

  test "campaign with custom base_url uses that URL" do
    campaign = Campaign.create!(
      name: "Custom URL Campaign",
      slug: "custom-url-test",
      theme: "flavortown",
      status: "open",
      referral_shards: 3,
      poster_shards: 1,
      required_coding_minutes: 60,
      base_url: "https://custom.example.com"
    )

    user = create_user
    poster = create_poster(user: user, campaign: campaign)

    assert_equal "https://custom.example.com/?ref=#{poster.referral_code}",
      poster.referral_url,
      "Campaign with custom base_url should use that URL"
  end

  test "campaign without subdomain falls back to slug" do
    campaign = Campaign.create!(
      name: "No Subdomain Campaign",
      slug: "no-subdomain",
      theme: "flavortown",
      status: "open",
      referral_shards: 3,
      poster_shards: 1,
      required_coding_minutes: 60,
      subdomain: nil
    )

    user = create_user
    poster = create_poster(user: user, campaign: campaign)

    assert_equal "https://no-subdomain.hack.club/?ref=#{poster.referral_code}",
      poster.referral_url,
      "Campaign without subdomain should use slug as subdomain"
  end

  # =============================================================================
  # QR CODE URL TESTS
  # =============================================================================

  test "qr_code_url uses pyramid base URL" do
    campaign = campaigns(:flavortown)
    user = create_user
    poster = create_poster(user: user, campaign: campaign)

    url = poster.qr_code_url

    assert_includes url, "/p/#{poster.qr_code_token}",
      "QR code URL should include /p/ path with token"
  end

  test "qr_code_token is 12 characters" do
    campaign = campaigns(:flavortown)
    user = create_user
    poster = create_poster(user: user, campaign: campaign)

    assert_equal 12, poster.qr_code_token.length,
      "QR code token should be 12 characters"
  end

  test "referral_code is 8 characters uppercase alphanumeric" do
    campaign = campaigns(:flavortown)
    user = create_user
    poster = create_poster(user: user, campaign: campaign)

    assert_equal 8, poster.referral_code.length,
      "Referral code should be 8 characters"
    assert_match(/^[A-Z0-9]+$/, poster.referral_code,
      "Referral code should be uppercase alphanumeric")
  end
end
