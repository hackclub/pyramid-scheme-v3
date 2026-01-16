# frozen_string_literal: true

require "test_helper"

class PosterGroupTest < ActiveSupport::TestCase
  setup do
    @user = users(:regular_user)
    @flavortown = campaigns(:flavortown)
  end

  # =============================================================================
  # VALIDATIONS
  # =============================================================================
  test "valid poster_group with required attributes" do
    group = PosterGroup.new(
      user: @user,
      campaign: @flavortown
    )
    assert group.valid?
  end

  test "name length validation" do
    group = PosterGroup.new(
      user: @user,
      campaign: @flavortown,
      name: "a" * 101  # Too long
    )
    assert_not group.valid?
    assert_includes group.errors[:name], "is too long (maximum is 100 characters)"
  end

  # =============================================================================
  # GENERATE POSTERS
  # =============================================================================
  test "generate_posters! creates specified number of posters" do
    group = PosterGroup.create!(user: @user, campaign: @flavortown)

    assert_difference -> { Poster.count }, 3 do
      group.generate_posters!(count: 3, poster_type: "color")
    end

    assert_equal 3, group.posters.count
  end

  test "generate_posters! raises error for invalid count" do
    group = PosterGroup.create!(user: @user, campaign: @flavortown)

    assert_raises(ArgumentError) do
      group.generate_posters!(count: 0)
    end

    assert_raises(ArgumentError) do
      group.generate_posters!(count: PosterGroup::MAX_POSTERS_PER_GROUP + 1)
    end
  end

  test "generate_posters! respects MAX_POSTERS_PER_GROUP" do
    assert_equal 10, PosterGroup::MAX_POSTERS_PER_GROUP
  end

  # =============================================================================
  # STATUS CHECKS
  # =============================================================================
  test "has_submitted_posters? returns false when all pending" do
    group = PosterGroup.create!(user: @user, campaign: @flavortown)
    group.generate_posters!(count: 2, poster_type: "color")

    assert_not group.has_submitted_posters?
  end

  test "has_submitted_posters? returns true when any non-pending" do
    group = PosterGroup.create!(user: @user, campaign: @flavortown)
    group.generate_posters!(count: 2, poster_type: "color")
    # Need to add location_description before transitioning to in_review
    poster = group.posters.first
    poster.update!(location_description: "Test location")
    poster.mark_in_review!

    assert group.has_submitted_posters?
  end

  test "all_submitted? returns false when any pending" do
    group = PosterGroup.create!(user: @user, campaign: @flavortown)
    group.generate_posters!(count: 2, poster_type: "color")

    assert_not group.all_submitted?
  end

  test "submission_summary returns correct counts" do
    group = PosterGroup.create!(user: @user, campaign: @flavortown)
    group.generate_posters!(count: 3, poster_type: "color")

    summary = group.submission_summary

    assert_equal 3, summary[:total]
    assert_equal 3, summary[:pending]
    assert_equal 0, summary[:in_review]
    assert_equal 0, summary[:success]
  end

  # =============================================================================
  # SCOPES
  # =============================================================================
  test "for_campaign scope filters by campaign" do
    group1 = PosterGroup.create!(user: @user, campaign: @flavortown)
    group2 = PosterGroup.create!(user: @user, campaign: campaigns(:aces))

    flavortown_groups = PosterGroup.for_campaign(@flavortown)

    assert_includes flavortown_groups, group1
    assert_not_includes flavortown_groups, group2
  end

  test "recent scope orders by created_at desc" do
    group1 = PosterGroup.create!(user: @user, campaign: @flavortown, created_at: 2.days.ago)
    group2 = PosterGroup.create!(user: @user, campaign: @flavortown, created_at: 1.day.ago)

    recent = PosterGroup.recent

    assert_equal group2, recent.first
    assert recent.to_a.index(group2) < recent.to_a.index(group1)
  end
end
