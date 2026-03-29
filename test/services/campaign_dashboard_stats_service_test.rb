# frozen_string_literal: true

require "test_helper"

class CampaignDashboardStatsServiceTest < ActiveSupport::TestCase
  test "referral stats use distinct statuses and consistent totals" do
    campaign = create_campaign(slug: "flavortown-stats-#{SecureRandom.hex(4)}")
    other_campaign = create_campaign(slug: "other-stats-#{SecureRandom.hex(4)}")
    referrer = create_user

    2.times { create_referral(referrer: referrer, campaign: campaign) }

    3.times do
      referral = create_referral(referrer: referrer, campaign: campaign)
      referral.update_columns(status: Referral.statuses[:id_verified], verified_at: Time.current)
    end

    4.times do
      referral = create_referral(referrer: referrer, campaign: campaign)
      referral.update_columns(
        status: Referral.statuses[:completed],
        verified_at: Time.current,
        completed_at: Time.current
      )
    end

    create_referral(referrer: referrer, campaign: other_campaign).update_columns(status: Referral.statuses[:completed], completed_at: Time.current)

    stats = CampaignDashboardStatsService.new(campaign: campaign).call.fetch(:referrals)

    assert_equal 2, stats[:pending]
    assert_equal 3, stats[:id_verified]
    assert_equal 4, stats[:completed]
    assert_equal 9, stats[:total]
  end
end
