# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  setup do
    @admin = users(:admin)
    @regular_user = users(:regular_user)
    @banned_user = users(:banned_user)
    @opted_out = users(:opted_out_user)
    @flavortown = campaigns(:flavortown)
  end

  # =============================================================================
  # VALIDATIONS
  # =============================================================================
  test "valid user with required attributes" do
    user = User.new(
      email: "new@example.com",
      display_name: "New User"
    )
    assert user.valid?
  end

  test "invalid without email" do
    user = User.new(display_name: "Test")
    assert_not user.valid?
    assert_includes user.errors[:email], "can't be blank"
  end

  test "invalid without display_name" do
    user = User.new(email: "test@example.com")
    assert_not user.valid?
    assert_includes user.errors[:display_name], "can't be blank"
  end

  test "email must be unique case-insensitively" do
    duplicate = User.new(
      email: @regular_user.email.upcase,
      display_name: "Duplicate"
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email], "has already been taken"
  end

  test "email is normalized to lowercase" do
    user = User.new(
      email: "TEST@EXAMPLE.COM",
      display_name: "Test"
    )
    user.valid?
    assert_equal "test@example.com", user.email
  end

  test "referral_code must be unique" do
    duplicate = User.new(
      email: "new@example.com",
      display_name: "New",
      referral_code: @regular_user.referral_code
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:referral_code], "has already been taken"
  end

  # =============================================================================
  # ROLES
  # =============================================================================
  test "admin? returns true for admin role" do
    assert @admin.admin?
  end

  test "admin? returns false for regular user" do
    assert_not @regular_user.admin?
  end

  test "fulfiller? returns true for fulfiller role" do
    fulfiller = users(:fulfiller)
    assert fulfiller.fulfiller?
  end

  test "fulfiller? returns true for admin" do
    # Admins should also have fulfiller access
    assert @admin.fulfiller?
  end

  # =============================================================================
  # SHARDS
  # =============================================================================
  test "credit_shards! increases total_shards" do
    initial = @regular_user.total_shards

    @regular_user.credit_shards!(10, transaction_type: "admin_grant")

    assert_equal initial + 10, @regular_user.total_shards
  end

  test "credit_shards! creates transaction record" do
    assert_difference -> { @regular_user.shard_transactions.count }, 1 do
      @regular_user.credit_shards!(10, transaction_type: "admin_grant", description: "Test credit")
    end
  end

  test "debit_shards! decreases total_shards" do
    @regular_user.update!(total_shards: 100)
    initial = @regular_user.total_shards

    @regular_user.debit_shards!(25, transaction_type: "admin_debit")

    assert_equal initial - 25, @regular_user.total_shards
  end

  test "debit_shards! raises InsufficientShardsError when not enough" do
    @regular_user.update!(total_shards: 10)

    assert_raises(User::InsufficientShardsError) do
      @regular_user.debit_shards!(20, transaction_type: "admin_debit")
    end
  end

  test "can_afford? returns true when user has enough shards" do
    @regular_user.update!(total_shards: 100)
    assert @regular_user.can_afford?(50)
  end

  test "can_afford? returns false when user doesn't have enough" do
    @regular_user.update!(total_shards: 10)
    assert_not @regular_user.can_afford?(50)
  end

  # =============================================================================
  # BANNING
  # =============================================================================
  test "ban! sets is_banned and timestamps" do
    @regular_user.ban!(reason: "Testing")

    assert @regular_user.is_banned?
    assert_not_nil @regular_user.banned_at
    assert_equal "Testing", @regular_user.banned_reason
  end

  test "unban! clears ban status" do
    @banned_user.unban!

    assert_not @banned_user.is_banned?
    assert_nil @banned_user.banned_at
    assert_nil @banned_user.banned_reason
  end

  # =============================================================================
  # REFERRAL CODES
  # =============================================================================
  test "generates referral_code on create" do
    user = User.create!(
      email: "newuser#{SecureRandom.hex(4)}@example.com",
      display_name: "New User"
    )

    assert_not_nil user.referral_code
    assert_equal 8, user.referral_code.length
    assert_match(/^[A-Z0-9]+$/, user.referral_code)
  end

  test "find_by_any_referral_code finds by standard code" do
    found = User.find_by_any_referral_code(@regular_user.referral_code)
    assert_equal @regular_user, found
  end

  test "find_by_any_referral_code is case-insensitive for standard codes" do
    found = User.find_by_any_referral_code(@regular_user.referral_code.downcase)
    assert_equal @regular_user, found
  end

  test "find_by_any_referral_code returns nil for blank code" do
    assert_nil User.find_by_any_referral_code("")
    assert_nil User.find_by_any_referral_code(nil)
  end

  test "effective_referral_code returns custom code when set" do
    @regular_user.update!(custom_referral_code: "MyCustomCode")
    assert_equal "MyCustomCode", @regular_user.effective_referral_code
  end

  test "effective_referral_code returns standard code when no custom" do
    @regular_user.update!(custom_referral_code: nil)
    assert_equal @regular_user.referral_code, @regular_user.effective_referral_code
  end

  # =============================================================================
  # WEEKLY POSTER LIMITS
  # =============================================================================
  test "weekly_paid_poster_limit includes base limit" do
    limit = @regular_user.weekly_paid_poster_limit
    assert limit >= User::BASE_WEEKLY_PAID_POSTERS
  end

  test "posters_created_this_week counts current week posters" do
    # Create a poster this week
    create_poster(user: @regular_user, campaign: @flavortown)

    assert @regular_user.posters_created_this_week > 0
  end

  test "remaining_paid_posters_this_week returns correct count" do
    remaining = @regular_user.remaining_paid_posters_this_week
    assert remaining >= 0
  end

  test "next_poster_will_be_paid? returns true under limit" do
    # Ensure user is under limit
    @regular_user.posters.where(
      created_at: Time.current.beginning_of_week..Time.current.end_of_week
    ).destroy_all

    assert @regular_user.next_poster_will_be_paid?
  end

  # =============================================================================
  # SCOPES
  # =============================================================================
  test "on_leaderboard excludes opted out users" do
    leaderboard_users = User.on_leaderboard
    leaderboard_users.each do |user|
      assert_not user.leaderboard_opted_out?
    end
  end

  test "on_leaderboard excludes banned users" do
    leaderboard_users = User.on_leaderboard
    leaderboard_users.each do |user|
      assert_not user.is_banned?
    end
  end

  test "search finds by display_name" do
    results = User.search(@regular_user.display_name[0..4])
    assert_includes results, @regular_user
  end

  test "search finds by email" do
    results = User.search(@regular_user.email.split("@").first)
    assert_includes results, @regular_user
  end

  # =============================================================================
  # CAMPAIGNS & EMBLEMS
  # =============================================================================
  test "participated_in? returns true when user has emblem" do
    # Use existing fixture emblem (regular_participant)
    assert @regular_user.participated_in?(@flavortown)
  end

  test "participated_in? returns false when user has no emblem" do
    @regular_user.user_emblems.destroy_all

    assert_not @regular_user.participated_in?(@flavortown)
  end
end
