# frozen_string_literal: true

class ReferralLeaderboardPeriod
  attr_reader :starts_at, :ends_at

  def self.current(reference_time = Time.current)
    time = reference_time.in_time_zone
    new(starts_at: time.beginning_of_month.beginning_of_day, ends_at: time.end_of_month.end_of_day)
  end

  def self.previous(reference_time = Time.current)
    current(reference_time.in_time_zone.prev_month)
  end

  def initialize(starts_at:, ends_at:)
    @starts_at = starts_at.in_time_zone
    @ends_at = ends_at.in_time_zone
  end

  def range
    starts_at..ends_at
  end

  def include?(time)
    range.cover?(time.in_time_zone)
  end

  def month_label
    starts_at.strftime("%B %Y")
  end

  def payout_label
    starts_at.strftime("%B %Y")
  end
end
