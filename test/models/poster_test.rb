# frozen_string_literal: true

require "test_helper"

class PosterTest < ActiveSupport::TestCase
  setup do
    @user = users(:regular_user)
    @campaign = campaigns(:flavortown)
    @pending_poster = posters(:pending_poster)
    @verified_poster = posters(:verified_poster)
  end

  # =============================================================================
  # VALIDATIONS
  # =============================================================================
  test "valid poster with all required attributes" do
    poster = Poster.new(
      user: @user,
      campaign: @campaign,
      qr_code_token: SecureRandom.alphanumeric(12),
      referral_code: SecureRandom.alphanumeric(8).upcase,
      poster_type: "color",
      verification_status: "pending"
    )
    assert poster.valid?
  end

  test "auto-generates qr_code_token on create" do
    poster = Poster.new(
      user: @user,
      campaign: @campaign,
      poster_type: "color"
    )
    assert_nil poster.qr_code_token
    poster.valid?  # Triggers before_validation
    assert_not_nil poster.qr_code_token
    assert_equal 12, poster.qr_code_token.length
  end

  test "auto-generates referral_code on create" do
    poster = Poster.new(
      user: @user,
      campaign: @campaign,
      poster_type: "color"
    )
    assert_nil poster.referral_code
    poster.valid?  # Triggers before_validation
    assert_not_nil poster.referral_code
    assert_equal 8, poster.referral_code.length
    assert_match(/\A[A-Z0-9]+\z/, poster.referral_code)
  end

  test "qr_code_token must be unique" do
    duplicate = Poster.new(
      user: @user,
      campaign: @campaign,
      qr_code_token: @pending_poster.qr_code_token,
      referral_code: SecureRandom.alphanumeric(8).upcase
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:qr_code_token], "has already been taken"
  end

  test "referral_code must be unique" do
    duplicate = Poster.new(
      user: @user,
      campaign: @campaign,
      qr_code_token: SecureRandom.alphanumeric(12),
      referral_code: @pending_poster.referral_code
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:referral_code], "has already been taken"
  end

  # =============================================================================
  # QR URL GENERATION - CRITICAL REGRESSION TEST
  # =============================================================================
  # This test ensures poster QR codes use the correct campaign subdomain
  # Regression: https://github.com/hackclub/pyramid/issues/XXX
  # Previously, all posters incorrectly used flavortown.hackclub.com instead of
  # the campaign's actual subdomain (e.g., aces.hack.club)

  test "referral_url uses correct campaign subdomain for flavortown" do
    poster = posters(:pending_poster)
    assert_equal campaigns(:flavortown), poster.campaign

    # Flavortown should use flavortown.hack.club
    url = poster.referral_url
    assert_match %r{^https://flavortown\.hack\.club/\?ref=#{poster.referral_code}$}, url,
      "Flavortown poster should use flavortown.hack.club domain"
  end

  test "referral_url uses correct campaign subdomain for aces" do
    poster = posters(:aces_poster)
    assert_equal campaigns(:aces), poster.campaign

    # Aces should use aces.hack.club
    url = poster.referral_url
    assert_match %r{^https://aces\.hack\.club/\?ref=#{poster.referral_code}$}, url,
      "Aces poster should use aces.hack.club domain"
  end

  test "referral_url uses correct campaign subdomain for construct" do
    poster = posters(:construct_poster)
    assert_equal campaigns(:construct), poster.campaign

    # Construct should use construct.hack.club
    url = poster.referral_url
    assert_match %r{^https://construct\.hack\.club/\?ref=#{poster.referral_code}$}, url,
      "Construct poster should use construct.hack.club domain"
  end

  test "referral_url never uses hackclub.com domain" do
    # This is a regression test - we previously had a bug where
    # the domain was incorrectly set to hackclub.com instead of hack.club
    [ posters(:pending_poster), posters(:aces_poster), posters(:construct_poster) ].each do |poster|
      url = poster.referral_url
      refute_match(/hackclub\.com/, url,
        "Poster referral_url should never use hackclub.com domain (found in #{poster.campaign.slug})")
    end
  end

  test "referral_url includes correct referral code" do
    poster = posters(:pending_poster)
    url = poster.referral_url

    assert_includes url, poster.referral_code,
      "Referral URL should include the poster's referral code"
    assert_includes url, "?ref=",
      "Referral URL should use ?ref= parameter"
  end

  test "qr_code_url points to pyramid base url with token" do
    poster = posters(:pending_poster)
    url = poster.qr_code_url

    assert_includes url, "/p/#{poster.qr_code_token}",
      "QR code URL should include /p/ path and token"
  end

  # =============================================================================
  # VERIFICATION STATUS TRANSITIONS
  # =============================================================================
  test "verify! transitions pending poster to success" do
    poster = create_poster(user: @user, campaign: @campaign)
    admin = users(:admin)

    stub_slack_notifications

    poster.verify!(admin)

    assert_equal "success", poster.verification_status
    assert_not_nil poster.verified_at
    assert_equal admin, poster.verified_by
  end

  test "verify! awards shards to user within weekly limit" do
    poster = create_poster(user: @user, campaign: @campaign)
    admin = users(:admin)
    initial_shards = @user.total_shards

    stub_slack_notifications

    poster.verify!(admin)
    @user.reload

    assert_equal initial_shards + @campaign.poster_shards, @user.total_shards
  end

  test "mark_in_review! transitions to in_review" do
    poster = create_poster(user: @user, campaign: @campaign)
    poster.update!(location_description: "Test location for proof submission")

    poster.mark_in_review!

    assert_equal "in_review", poster.verification_status
  end

  test "reject! transitions to rejected with reason" do
    poster = create_poster(user: @user, campaign: @campaign)
    admin = users(:admin)
    reason = "QR code not visible"

    poster.reject!(reason, admin)

    assert_equal "rejected", poster.verification_status
    assert_equal reason, poster.rejection_reason
    assert_equal admin, poster.verified_by
  end

  test "mark_digital! transitions pending poster to digital" do
    poster = create_poster(user: @user, campaign: @campaign)
    admin = users(:admin)

    poster.mark_digital!(admin)

    assert_equal "digital", poster.verification_status
    assert_not_nil poster.verified_at
  end

  test "mark_digital! fails for non-pending poster" do
    poster = create_poster(user: @user, campaign: @campaign, verification_status: "in_review")
    admin = users(:admin)

    assert_raises(ActiveRecord::RecordInvalid) do
      poster.mark_digital!(admin)
    end
  end

  # =============================================================================
  # LOCATION HANDLING
  # =============================================================================
  test "location_editable? returns true for pending poster" do
    poster = posters(:pending_poster)
    assert poster.location_editable?
  end

  test "location_editable? returns false for non-pending poster" do
    poster = posters(:in_review_poster)
    assert_not poster.location_editable?
  end

  # =============================================================================
  # SCOPES
  # =============================================================================
  test "pending scope returns only pending posters" do
    pending_posters = Poster.pending
    pending_posters.each do |poster|
      assert_equal "pending", poster.verification_status
    end
  end

  test "success scope returns only verified posters" do
    verified_posters = Poster.success
    verified_posters.each do |poster|
      assert_equal "success", poster.verification_status
    end
  end

  test "for_campaign scope filters by campaign" do
    campaign_posters = Poster.for_campaign(@campaign)
    campaign_posters.each do |poster|
      assert_equal @campaign, poster.campaign
    end
  end

  # =============================================================================
  # AUTO-GENERATED TOKENS
  # =============================================================================
  test "generates qr_code_token on create" do
    poster = Poster.new(user: @user, campaign: @campaign)
    poster.valid?

    assert_not_nil poster.qr_code_token
    assert_equal 12, poster.qr_code_token.length
  end

  test "generates referral_code on create" do
    poster = Poster.new(user: @user, campaign: @campaign)
    poster.valid?

    assert_not_nil poster.referral_code
    assert_equal 8, poster.referral_code.length
    assert_match(/^[A-Z0-9]+$/, poster.referral_code)
  end

  # =============================================================================
  # SCAN TRACKING
  # =============================================================================
  test "record_scan! creates poster_scan" do
    poster = posters(:verified_poster)

    assert_difference -> { poster.poster_scans.count }, 1 do
      poster.record_scan!(
        ip_address: "192.168.1.1",
        user_agent: "Mozilla/5.0",
        country_code: "US"
      )
    end
  end

  test "scan_count returns correct count" do
    poster = posters(:verified_poster)
    initial_count = poster.scan_count

    poster.record_scan!(ip_address: "1.1.1.1")
    poster.record_scan!(ip_address: "2.2.2.2")

    assert_equal initial_count + 2, poster.scan_count
  end
end
