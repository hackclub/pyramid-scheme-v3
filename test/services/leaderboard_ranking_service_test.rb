# frozen_string_literal: true

require "test_helper"
require "ostruct"

class LeaderboardRankingServiceTest < ActiveSupport::TestCase
  setup do
    @users = [
      OpenStruct.new(id: 1, campaign_referral_count: 10, referral_count: 10),
      OpenStruct.new(id: 2, campaign_referral_count: 10, referral_count: 10),
      OpenStruct.new(id: 3, campaign_referral_count: 5, referral_count: 5),
      OpenStruct.new(id: 4, campaign_referral_count: 0, referral_count: 0)
    ]
  end

  test "calculate_ranks returns empty for non-referrals category" do
    service = LeaderboardRankingService.new(leaders: @users, category: "posters", page: 1)
    assert_empty service.calculate_ranks
  end

  test "calculate_ranks returns empty for page 2" do
    service = LeaderboardRankingService.new(leaders: @users, category: "referrals", page: 2)
    assert_empty service.calculate_ranks
  end

  test "calculate_ranks handles ties with dense ranking" do
    service = LeaderboardRankingService.new(leaders: @users, category: "referrals", page: 1)
    ranks = service.calculate_ranks

    # Users 1 and 2 should share rank 1 (tied at 10 referrals)
    assert_equal 1, ranks[1][:rank]
    assert_equal 1, ranks[2][:rank]

    # User 3 should be rank 2 (5 referrals)
    assert_equal 2, ranks[3][:rank]

    # User 4 should not have a rank (0 referrals)
    assert_nil ranks[4]
  end

  test "calculate_prizes distributes prizes correctly with ties" do
    service = LeaderboardRankingService.new(leaders: @users, category: "referrals", page: 1)
    ranks = service.calculate_ranks
    prizes = service.calculate_prizes(ranks)

    # Two users at rank 1 should split 50 shards (25 each)
    assert_equal 25, prizes[1][:shards]
    assert_equal 25, prizes[2][:shards]

    # User at rank 2 should get full 25 shards
    assert_equal 25, prizes[3][:shards]
  end

  test "calculate_prizes returns empty for non-referrals category" do
    service = LeaderboardRankingService.new(leaders: @users, category: "shards", page: 1)
    ranks = service.calculate_ranks
    prizes = service.calculate_prizes(ranks)

    assert_empty prizes
  end
end
