# frozen_string_literal: true

class CampaignDashboardStatsService
  def initialize(campaign:)
    @campaign = campaign
  end

  def call
    {
      campaign: {
        id: campaign.id,
        name: campaign.name,
        slug: campaign.slug
      },
      referrals: referral_stats,
      posters: poster_stats,
      activity: activity_stats
    }
  end

  private

  attr_reader :campaign

  def referral_stats
    scoped_referrals = campaign.referrals

    {
      pending: scoped_referrals.where.not(status: :completed).count,
      id_verified: scoped_referrals.id_verified.count,
      completed: scoped_referrals.completed.count,
      total: scoped_referrals.count
    }
  end

  def poster_stats
    scoped_posters = campaign.posters

    {
      pending_physical: scoped_posters.where(verification_status: %w[pending in_review on_hold]).count,
      rejected_physical: scoped_posters.rejected.count,
      completed_physical: scoped_posters.success.count,
      completed_digital: scoped_posters.digital.count,
      total: scoped_posters.count
    }
  end

  def activity_stats
    engaged_user_ids = (
      campaign.user_emblems.distinct.pluck(:user_id) +
      campaign.referrals.where.not(referrer_id: nil).distinct.pluck(:referrer_id) +
      campaign.posters.where.not(user_id: nil).distinct.pluck(:user_id)
    ).compact.uniq

    {
      engaged_users: engaged_user_ids.count,
      engaged_user_slack_ids: User.where(id: engaged_user_ids).where.not(slack_id: [ nil, "" ]).distinct.pluck(:slack_id),
      total_hours_logged: (campaign.referrals.sum(:tracked_minutes).to_f / 60).round(1),
      timeline: activity_timeline
    }
  end

  def activity_timeline
    start_date = activity_start_date
    end_date = Time.current.to_date
    date_range = start_date..end_date

    referral_creations = grouped_counts(campaign.referrals, :created_at)
    referral_verifications = grouped_counts(campaign.referrals.where.not(verified_at: nil), :verified_at)
    referral_completions = grouped_counts(campaign.referrals.completed.where.not(completed_at: nil), :completed_at)
    poster_creations = grouped_counts(campaign.posters, :created_at)
    poster_approvals = grouped_counts(
      campaign.posters.where(verification_status: %w[success digital]).where.not(verified_at: nil),
      :verified_at
    )
    poster_rejections = grouped_counts(campaign.posters.rejected, :updated_at)

    date_range.map do |date|
      {
        date: date.iso8601,
        referrals_created: referral_creations[date] || 0,
        referrals_verified: referral_verifications[date] || 0,
        referrals_completed: referral_completions[date] || 0,
        posters_created: poster_creations[date] || 0,
        posters_approved: poster_approvals[date] || 0,
        posters_rejected: poster_rejections[date] || 0
      }
    end
  end

  def activity_start_date
    earliest_timestamp = [
      campaign.referrals.minimum(:created_at),
      campaign.referrals.minimum(:verified_at),
      campaign.referrals.minimum(:completed_at),
      campaign.posters.minimum(:created_at),
      campaign.posters.minimum(:verified_at),
      campaign.posters.rejected.minimum(:updated_at)
    ].compact.min

    (earliest_timestamp || Time.current).to_date
  end

  def grouped_counts(scope, column)
    scope.group(Arel.sql("DATE(#{column})")).count
  end
end
