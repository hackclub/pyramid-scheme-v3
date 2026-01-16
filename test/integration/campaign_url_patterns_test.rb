# frozen_string_literal: true

require "test_helper"

class CampaignUrlPatternsTest < ActiveSupport::TestCase
  # =============================================================================
  # CRITICAL URL PATTERN TESTS
  # =============================================================================
  # These tests ensure the complete URL flow for each campaign:
  # 1. User referral link: campaign.hack.club/?ref=CODE
  # 2. Poster QR scan goes through: pyramid.hackclub.com/p/TOKEN
  # 3. Proxy redirects: campaign.hack.club/CODE -> campaign.hackclub.com/?ref=CODE
  # =============================================================================

  setup do
    @flavortown = campaigns(:flavortown)
    @aces = campaigns(:aces)
    @construct = campaigns(:construct)
  end

  # =============================================================================
  # CONSTRUCT CAMPAIGN URL PATTERNS
  # =============================================================================
  test "construct referral URL uses construct.hack.club domain" do
    logic = ConstructCampaignLogic.new(@construct)
    url = logic.referral_url_for("TESTCODE")

    assert_equal "https://construct.hack.club/?ref=TESTCODE", url,
      "Construct referral URL must use construct.hack.club domain"
  end

  test "construct poster referral_url uses construct.hack.club" do
    poster = posters(:construct_poster)
    url = poster.referral_url

    assert_match %r{^https://construct\.hack\.club/\?ref=#{poster.referral_code}$}, url,
      "Construct poster referral_url must use construct.hack.club"
  end

  test "construct poster URL never uses hackclub.com directly" do
    poster = posters(:construct_poster)
    url = poster.referral_url

    # URL should use hack.club, NOT hackclub.com
    assert_match(/construct\.hack\.club/, url,
      "Construct poster URL must use hack.club domain (not hackclub.com)")
    refute_match(/construct\.hackclub\.com/, url,
      "Construct poster URL must NOT use hackclub.com domain - proxy handles redirect")
  end

  test "construct campaign logic base URL is construct.hack.club" do
    logic = BaseCampaignLogic.for(@construct)
    assert_equal "https://construct.hack.club", logic.referral_base_url,
      "Construct base URL must be construct.hack.club"
  end

  # =============================================================================
  # ACES CAMPAIGN URL PATTERNS
  # =============================================================================
  test "aces referral URL uses aces.hack.club domain" do
    logic = AcesCampaignLogic.new(@aces)
    url = logic.referral_url_for("TESTCODE")

    assert_equal "https://aces.hack.club/?ref=TESTCODE", url,
      "Aces referral URL must use aces.hack.club domain"
  end

  test "aces poster referral_url uses aces.hack.club" do
    poster = posters(:aces_poster)
    url = poster.referral_url

    assert_match %r{^https://aces\.hack\.club/\?ref=#{poster.referral_code}$}, url,
      "Aces poster referral_url must use aces.hack.club"
  end

  test "aces poster URL never uses hackclub.com directly" do
    poster = posters(:aces_poster)
    url = poster.referral_url

    # URL should use hack.club, NOT hackclub.com
    assert_match(/aces\.hack\.club/, url,
      "Aces poster URL must use hack.club domain (not hackclub.com)")
    refute_match(/aces\.hackclub\.com/, url,
      "Aces poster URL must NOT use hackclub.com domain - proxy handles redirect")
  end

  test "aces campaign logic base URL is aces.hack.club" do
    logic = BaseCampaignLogic.for(@aces)
    assert_equal "https://aces.hack.club", logic.referral_base_url,
      "Aces base URL must be aces.hack.club"
  end

  # =============================================================================
  # FLAVORTOWN CAMPAIGN URL PATTERNS (reference for consistency)
  # =============================================================================
  test "flavortown referral URL uses flavortown.hack.club domain" do
    logic = FlavortownCampaignLogic.new(@flavortown)
    url = logic.referral_url_for("TESTCODE")

    assert_equal "https://flavortown.hack.club/?ref=TESTCODE", url,
      "Flavortown referral URL must use flavortown.hack.club domain"
  end

  test "flavortown poster referral_url uses flavortown.hack.club" do
    poster = posters(:pending_poster)
    url = poster.referral_url

    assert_match %r{^https://flavortown\.hack\.club/\?ref=#{poster.referral_code}$}, url,
      "Flavortown poster referral_url must use flavortown.hack.club"
  end

  # =============================================================================
  # QR CODE URL PATTERNS
  # =============================================================================
  test "QR codes use pyramid base URL not campaign domain" do
    # QR codes should point to the Pyramid app (/p/TOKEN) which then
    # redirects appropriately - this is different from referral URLs
    poster = posters(:construct_poster)
    qr_url = poster.qr_code_url

    # QR URL should include /p/ path with the token
    assert_includes qr_url, "/p/#{poster.qr_code_token}",
      "QR URL should use /p/ path with poster token"

    # QR URL should NOT point directly to campaign domain
    refute_match(/construct\.hack\.club/, qr_url,
      "QR URL should not point directly to campaign domain")
  end

  test "construct poster QR referral_url matches campaign logic" do
    poster = posters(:construct_poster)
    logic = BaseCampaignLogic.for(poster.campaign)

    # The poster's referral_url should exactly match what campaign logic generates
    expected = logic.referral_url_for(poster.referral_code)
    assert_equal expected, poster.referral_url,
      "Poster referral_url must match campaign logic output"
  end

  test "aces poster QR referral_url matches campaign logic" do
    poster = posters(:aces_poster)
    logic = BaseCampaignLogic.for(poster.campaign)

    expected = logic.referral_url_for(poster.referral_code)
    assert_equal expected, poster.referral_url,
      "Poster referral_url must match campaign logic output"
  end

  # =============================================================================
  # URL PATTERN CONSISTENCY ACROSS ALL CAMPAIGNS
  # =============================================================================
  test "all active campaigns have consistent URL patterns" do
    Campaign.active.each do |campaign|
      user = create_user
      poster = create_poster(user: user, campaign: campaign)
      logic = BaseCampaignLogic.for(campaign)

      # Check referral URL format
      referral_url = poster.referral_url
      expected_url = logic.referral_url_for(poster.referral_code)

      assert_equal expected_url, referral_url,
        "Campaign #{campaign.slug}: poster referral_url must match logic output"

      # Verify URL uses hack.club domain
      assert_match(/\.hack\.club/, referral_url,
        "Campaign #{campaign.slug}: URL must use .hack.club domain")

      # Verify URL format is correct
      assert_match(/\?ref=[A-Z0-9]{8}$/, referral_url,
        "Campaign #{campaign.slug}: URL must end with ?ref=CODE format")
    end
  end

  # =============================================================================
  # PROXY DOMAIN MAPPING VERIFICATION
  # =============================================================================
  # These tests document the expected proxy behavior. The proxy service
  # maps construct.hack.club -> construct.hackclub.com, etc.
  # The Rails app generates construct.hack.club URLs, proxy handles redirect.

  test "construct URL flow documentation" do
    # This test documents the expected URL flow for construct:
    # 1. Poster QR code contains: https://pyramid.hackclub.com/p/TOKEN
    # 2. Scanning QR hits Pyramid, looks up poster, redirects to referral_url
    # 3. Referral URL is: https://construct.hack.club/?ref=CODE
    # 4. Proxy at construct.hack.club redirects to: https://construct.hackclub.com/?ref=CODE
    #
    # Direct link flow:
    # 1. User shares: https://construct.hack.club/?ref=CODE
    # 2. Proxy redirects to: https://construct.hackclub.com/?ref=CODE
    # 3. User also may share: construct.hack.club/CODE (without ?ref=)
    # 4. Proxy validates code, redirects to: https://construct.hackclub.com/?ref=CODE

    poster = posters(:construct_poster)

    # Step 1 & 2: QR scan URL
    qr_url = poster.qr_code_url
    assert_includes qr_url, "/p/#{poster.qr_code_token}"

    # Step 3: Referral URL that users see
    referral_url = poster.referral_url
    assert_equal "https://construct.hack.club/?ref=#{poster.referral_code}", referral_url
  end

  test "aces URL flow documentation" do
    # Same flow as construct but for aces campaign
    poster = posters(:aces_poster)

    qr_url = poster.qr_code_url
    assert_includes qr_url, "/p/#{poster.qr_code_token}"

    referral_url = poster.referral_url
    assert_equal "https://aces.hack.club/?ref=#{poster.referral_code}", referral_url
  end
end
