# frozen_string_literal: true

require "test_helper"

class ReferralTest < ActiveSupport::TestCase
  setup do
    @referrer = users(:regular_user)
    @admin = users(:admin)
    @flavortown = campaigns(:flavortown)
    @pending_referral = referrals(:pending_referral)
    @completed_referral = referrals(:completed_referral)
  end

  # =============================================================================
  # VALIDATIONS
  # =============================================================================
  test "valid referral with required attributes" do
    referral = Referral.new(
      referrer: @referrer,
      campaign: @flavortown,
      referred_identifier: "newperson@example.com",
      referral_type: "link"
    )
    assert referral.valid?
  end

  test "invalid without referred_identifier" do
    referral = Referral.new(
      referrer: @referrer,
      campaign: @flavortown
    )
    assert_not referral.valid?
    assert_includes referral.errors[:referred_identifier], "can't be blank"
  end

  test "referred_identifier must be unique per referrer" do
    duplicate = Referral.new(
      referrer: @pending_referral.referrer,
      campaign: @flavortown,
      referred_identifier: @pending_referral.referred_identifier,
      referral_type: "link"
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:referred_identifier], "has already been referred by you"
  end

  test "same identifier can be referred by different users" do
    referral = Referral.new(
      referrer: @admin,
      campaign: @flavortown,
      referred_identifier: @pending_referral.referred_identifier,
      referral_type: "link"
    )
    assert referral.valid?
  end

  test "referral_type must be valid" do
    invalid_types = [ "invalid", "", "email" ]
    invalid_types.each do |type|
      referral = Referral.new(
        referrer: @referrer,
        campaign: @flavortown,
        referred_identifier: "test#{SecureRandom.hex}@example.com",
        referral_type: type
      )
      assert_not referral.valid?, "Expected referral_type '#{type}' to be invalid"
    end
  end

  test "valid referral_types" do
    %w[link poster].each do |type|
      referral = Referral.new(
        referrer: @referrer,
        campaign: @flavortown,
        referred_identifier: "#{type}test#{SecureRandom.hex}@example.com",
        referral_type: type
      )
      assert referral.valid?, "Expected referral_type '#{type}' to be valid"
    end
  end

  # =============================================================================
  # STATUS ENUM
  # =============================================================================
  test "status enum values" do
    referral = Referral.new(status: :pending)
    assert referral.pending?

    referral.status = :id_verified
    assert referral.id_verified?

    referral.status = :completed
    assert referral.completed?
  end

  # =============================================================================
  # STATUS TRANSITIONS
  # =============================================================================
  test "verify_identity! transitions pending to id_verified" do
    referral = create_referral(referrer: @referrer, campaign: @flavortown)

    referral.verify_identity!

    assert referral.id_verified?
    assert_not_nil referral.verified_at
  end

  test "verify_identity! does nothing for already verified" do
    referral = create_referral(referrer: @referrer, campaign: @flavortown, status: :id_verified)
    original_verified_at = referral.verified_at

    referral.verify_identity!

    assert referral.id_verified?
    assert_nil referral.verified_at
  end

  test "complete! requires id_verified status" do
    referral = create_referral(
      referrer: @referrer,
      campaign: @flavortown,
      status: :pending,
      tracked_minutes: 120
    )

    referral.complete!

    # Should still be pending because not id_verified
    assert referral.pending?
  end

  test "complete! requires minimum tracked_minutes" do
    referral = create_referral(
      referrer: @referrer,
      campaign: @flavortown,
      status: :id_verified,
      tracked_minutes: 30  # Less than required 60
    )

    referral.complete!

    # Should still be id_verified
    assert referral.id_verified?
  end

  test "complete! transitions to completed with proper conditions" do
    referral = create_referral(
      referrer: @referrer,
      campaign: @flavortown,
      status: :id_verified,
      tracked_minutes: 120
    )

    stub_slack_notifications

    referral.complete!

    assert referral.completed?
    assert_not_nil referral.completed_at
  end

  # =============================================================================
  # SCOPES
  # =============================================================================
  test "for_campaign scope filters by campaign" do
    referrals = Referral.for_campaign(@flavortown)
    referrals.each do |referral|
      assert_equal @flavortown, referral.campaign
    end
  end

  test "by_referrer scope filters by referrer" do
    referrals = Referral.by_referrer(@referrer)
    referrals.each do |referral|
      assert_equal @referrer, referral.referrer
    end
  end

  test "from_links scope returns only link referrals" do
    referrals = Referral.from_links
    referrals.each do |referral|
      assert_equal "link", referral.referral_type
    end
  end

  test "from_posters scope returns only poster referrals" do
    referrals = Referral.from_posters
    referrals.each do |referral|
      assert_equal "poster", referral.referral_type
    end
  end

  # =============================================================================
  # STATUS LABELS
  # =============================================================================
  test "pending_status_label returns Pending for basic pending" do
    referral = create_referral(referrer: @referrer, campaign: @flavortown, status: :pending)
    referral.update_column(:metadata, {})

    assert_equal "Pending", referral.pending_status_label
  end

  test "pending_status_label returns nil for non-pending" do
    assert_nil @completed_referral.pending_status_label
  end
end
