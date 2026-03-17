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
      total_users: total_user_count,
      user_slack_ids: slack_ids_for(internal_user_ids),
      engaged_users: engaged_user_ids.count,
      engaged_user_slack_ids: slack_ids_for(engaged_user_ids),
      total_hours_logged: total_hours_logged,
      timeline: activity_timeline
    }
  end

  def total_hours_logged
    airtable_hours = campaign.airtable_referrals.sum(Arel.sql("COALESCE((metadata->>'hours')::numeric, 0)"))
    return airtable_hours.to_f.round(1) if airtable_hours.to_f.positive?

    (campaign.referrals.sum(:tracked_minutes).to_f / 60).round(1)
  end

  def slack_ids_for(user_ids)
    User.where(id: user_ids).where.not(slack_id: [ nil, "" ]).distinct.pluck(:slack_id)
  end

  def total_user_count
    internal_count = internal_user_ids.count
    external_count = external_user_identifiers.count
    deduped_external_count = (external_user_identifiers - internal_user_emails).count

    internal_count + deduped_external_count
  end

  def internal_user_ids
    @internal_user_ids ||= (
      campaign.user_emblems.distinct.pluck(:user_id) +
      campaign.referrals.where.not(referrer_id: nil).distinct.pluck(:referrer_id) +
      campaign.referrals.where.not(referred_id: nil).distinct.pluck(:referred_id) +
      campaign.posters.where.not(user_id: nil).distinct.pluck(:user_id)
    ).compact.uniq
  end

  def external_user_identifiers
    @external_user_identifiers ||= (
      campaign.referrals.where.not(referred_identifier: [ nil, "" ]).distinct.pluck(:referred_identifier) +
      campaign.airtable_referrals.where.not(email: [ nil, "" ]).distinct.pluck(:email)
    ).filter_map { |identifier| normalize_identifier(identifier) }.uniq
  end

  def internal_user_emails
    @internal_user_emails ||= User.where(id: internal_user_ids)
                                  .where.not(email: [ nil, "" ])
                                  .distinct
                                  .pluck(:email)
                                  .filter_map { |email| normalize_identifier(email) }
                                  .uniq
  end

  def normalize_identifier(value)
    value.to_s.strip.downcase.presence
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
