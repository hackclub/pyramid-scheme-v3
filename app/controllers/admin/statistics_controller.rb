# frozen_string_literal: true

module Admin
  class StatisticsController < BaseController
    def index
      @range = params[:range] || "1m"
      @start_date = range_to_start_date(@range)
    end

    def data
      range = params[:range] || "1m"
      chart_type = params[:type] || "users"
      start_date = range_to_start_date(range)

      data = case chart_type
      when "users"
        User.where("created_at >= ?", start_date)
          .group_by_day(:created_at)
          .count
      when "referrals"
        Referral.where("created_at >= ?", start_date)
          .group_by_day(:created_at)
          .count
      when "completed_referrals"
        Referral.where("completed_at >= ?", start_date)
          .group_by_day(:completed_at)
          .count
      when "verified_posters"
        Poster.where(verification_status: "success")
          .where("verified_at >= ?", start_date)
          .group_by_day(:verified_at)
          .count
      when "proxy_hits"
        ReferralCodeLog.where("created_at >= ?", start_date)
          .group_by_day(:created_at)
          .count
      when "poster_scans"
        PosterScan.where("created_at >= ?", start_date)
          .group_by_day(:created_at)
          .count
      else
        {}
      end

      render json: {
        labels: data.keys.map { |d| d.strftime("%b %d") },
        values: data.values
      }
    end

    private

    def range_to_start_date(range)
      case range
      when "1d"
        1.day.ago.beginning_of_day
      when "5d"
        5.days.ago.beginning_of_day
      when "1m"
        1.month.ago.beginning_of_day
      when "3m"
        3.months.ago.beginning_of_day
      when "1y"
        1.year.ago.beginning_of_day
      when "all"
        10.years.ago
      else
        1.month.ago.beginning_of_day
      end
    end

    # Simple group_by_day helper if groupdate gem isn't available
    def self.group_by_day(records, column)
      records.group("DATE(#{column})").order("DATE(#{column})")
    end
  end
end

# Extend ActiveRecord with group_by_day if not using groupdate gem
unless ActiveRecord::Relation.method_defined?(:group_by_day)
  module GroupByDayExtension
    def group_by_day(column)
      group("DATE(#{column})").order("DATE(#{column})")
    end
  end
  ActiveRecord::Relation.include(GroupByDayExtension)
end
