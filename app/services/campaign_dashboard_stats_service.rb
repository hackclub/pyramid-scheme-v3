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
      referrals: safe_section(default_referral_stats) { referral_stats },
      posters: safe_section(default_poster_stats) { poster_stats },
      activity: safe_section(default_activity_stats) { activity_stats }
    }.tap { |payload| payload[:partial_data] = true if @partial_data }
  end

  private

  attr_reader :campaign

  def default_referral_stats
    {
      pending: 0,
      id_verified: 0,
      completed: 0,
      total: 0
    }
  end

  def default_poster_stats
    {
      pending_physical: 0,
      rejected_physical: 0,
      completed_physical: 0,
      completed_digital: 0,
      total: 0
    }
  end

  def default_activity_stats
    {
      all_users: 0,
      total_users: 0,
      users_with_activity: 0,
      user_slack_ids: [],
      engaged_users: 0,
      engaged_user_slack_ids: [],
      total_hours_logged: 0,
      users_gained_last_week: 0,
      users_gained_previous_week: 0,
      verified_hours_last_week: 0,
      verified_hours_previous_week: 0,
      shipped_projects: 0,
      timeline: []
    }
  end

  def safe_section(fallback)
    yield
  rescue StandardError => e
    @partial_data = true
    Rails.logger.error("[CampaignDashboardStatsService] #{e.class}: #{e.message}")
    Rails.logger.error("[CampaignDashboardStatsService] #{e.backtrace.first}")
    fallback
  end

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
      all_users: User.count,
      total_users: user_first_seen_dates_by_entity.count,
      users_with_activity: user_first_seen_dates_by_entity.count,
      user_slack_ids: slack_ids_for(internal_user_ids),
      engaged_users: engaged_user_ids.count,
      engaged_user_slack_ids: slack_ids_for(engaged_user_ids),
      total_hours_logged: total_hours_logged,
      users_gained_last_week: sum_last_n_days(user_additions_by_date, 7).to_i,
      users_gained_previous_week: sum_previous_n_days(user_additions_by_date, 7).to_i,
      verified_hours_last_week: sum_last_n_days(verified_hours_by_date, 7).round(1),
      verified_hours_previous_week: sum_previous_n_days(verified_hours_by_date, 7).round(1),
      shipped_projects: shipped_projects_count,
      timeline: activity_timeline
    }
  end

  def total_hours_logged
    verified_hours = completed_referral_hours.sum
    return verified_hours.round(1) if verified_hours.positive?

    completed_referrals = campaign.referrals.completed
    return 0 if completed_referrals.none?

    (completed_referrals.sum(:tracked_minutes).to_f / 60).round(1)
  end

  def shipped_projects_count
    campaign.airtable_referrals.where("(metadata->>'projects_shipped') IS NOT NULL")
                               .where("(metadata->>'projects_shipped')::int > 0")
                               .count
  end

  def slack_ids_for(user_ids)
    User.where(id: user_ids).where.not(slack_id: [ nil, "" ]).distinct.pluck(:slack_id)
  end

  def internal_user_ids
    @internal_user_ids ||= (
      campaign.user_emblems.distinct.pluck(:user_id) +
      campaign.referrals.where.not(referrer_id: nil).distinct.pluck(:referrer_id) +
      campaign.referrals.where.not(referred_id: nil).distinct.pluck(:referred_id) +
      campaign.posters.where.not(user_id: nil).distinct.pluck(:user_id)
    ).compact.uniq
  end

  def internal_user_email_index
    @internal_user_email_index ||= User.where(id: internal_user_ids)
                                       .pluck(:id, :email)
                                       .to_h
                                       .transform_values { |email| normalize_identifier(email) }
  end

  def normalize_identifier(value)
    value.to_s.strip.downcase.presence
  end

  def completed_referral_identifiers
    @completed_referral_identifiers ||= campaign.referrals.completed
                                               .where.not(referred_identifier: [ nil, "" ])
                                               .distinct
                                               .pluck(:referred_identifier)
                                               .filter_map { |identifier| normalize_identifier(identifier) }
                                               .uniq
  end

  def completed_referral_hours
    @completed_referral_hours ||= completed_referral_identifiers.map { |identifier| airtable_hours_by_identifier[identifier].to_f }
  end

  def airtable_hours_by_identifier
    @airtable_hours_by_identifier ||= campaign.airtable_referrals.find_each.with_object(Hash.new(0.0)) do |record, index|
      identifier = normalize_identifier(record.email)
      next if identifier.blank?

      index[identifier] += record.hours.to_f
    end
  end

  def user_first_seen_dates_by_entity
    @user_first_seen_dates_by_entity ||= begin
      first_seen = {}

      campaign.user_emblems.select(:id, :user_id, :earned_at).find_each do |emblem|
        track_first_seen(first_seen, identity_key_for_user_id(emblem.user_id), emblem.earned_at)
      end

      campaign.referrals.select(:id, :referrer_id, :referred_id, :referred_identifier, :created_at).find_each do |referral|
        track_first_seen(first_seen, identity_key_for_user_id(referral.referrer_id), referral.created_at)
        track_first_seen(first_seen, identity_key_for_user_id(referral.referred_id), referral.created_at)
        track_first_seen(first_seen, identity_key_for_identifier(referral.referred_identifier), referral.created_at)
      end

      campaign.posters.select(:id, :user_id, :created_at).find_each do |poster|
        track_first_seen(first_seen, identity_key_for_user_id(poster.user_id), poster.created_at)
      end

      campaign.airtable_referrals.select(:id, :email, :created_at, :synced_at).find_each do |record|
        track_first_seen(first_seen, identity_key_for_identifier(record.email), record.synced_at || record.created_at)
      end

      first_seen
    end
  end

  def user_additions_by_date
    @user_additions_by_date ||= user_first_seen_dates_by_entity.values.each_with_object(Hash.new(0)) do |date, counts|
      counts[date] += 1
    end
  end

  def verified_hours_by_date
    @verified_hours_by_date ||= begin
      campaign.referrals.completed.where.not(completed_at: nil).pluck(:completed_at, :referred_identifier).each_with_object(Hash.new(0.0)) do |(completed_at, identifier), counts|
        normalized_identifier = normalize_identifier(identifier)
        next if completed_at.blank? || normalized_identifier.blank?

        counts[completed_at.to_date] += airtable_hours_by_identifier[normalized_identifier]
      end.transform_values { |hours| hours.round(1) }
    end
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
        users_added: user_additions_by_date[date] || 0,
        referrals_created: referral_creations[date] || 0,
        referrals_verified: referral_verifications[date] || 0,
        referrals_completed: referral_completions[date] || 0,
        verified_hours: verified_hours_by_date[date] || 0,
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
      user_first_seen_dates_by_entity.values.min,
      campaign.posters.minimum(:created_at),
      campaign.posters.minimum(:verified_at),
      campaign.posters.rejected.minimum(:updated_at)
    ].compact.min

    (earliest_timestamp || Time.current).to_date
  end

  def grouped_counts(scope, column)
    scope.group(Arel.sql("DATE(#{column})")).count
  end

  def identity_key_for_user_id(user_id)
    return if user_id.blank?

    email = internal_user_email_index[user_id]
    return "email:#{email}" if email.present?

    "user:#{user_id}"
  end

  def identity_key_for_identifier(identifier)
    normalized_identifier = normalize_identifier(identifier)
    return if normalized_identifier.blank?

    "email:#{normalized_identifier}"
  end

  def track_first_seen(index, entity_key, timestamp)
    return if entity_key.blank? || timestamp.blank?

    date = timestamp.to_date
    current_date = index[entity_key]
    index[entity_key] = current_date.nil? || date < current_date ? date : current_date
  end

  def sum_last_n_days(counts, days)
    date_range_for_last_n_days(days).sum { |date| counts[date].to_f }
  end

  def sum_previous_n_days(counts, days)
    end_date = days.days.ago.to_date
    start_date = ((days * 2) - 1).days.ago.to_date
    (start_date..end_date).sum { |date| counts[date].to_f }
  end

  def date_range_for_last_n_days(days)
    (days - 1).days.ago.to_date..Time.current.to_date
  end
end
