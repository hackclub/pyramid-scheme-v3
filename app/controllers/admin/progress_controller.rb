# frozen_string_literal: true

module Admin
  class ProgressController < BaseController
    def index
      # Get v2 start date
      @v2_start_date = Date.new(2025, 6, 15)

      # Get v3 start date (first referral or poster)
      @v3_start_date = [
        Referral.minimum(:created_at),
        Poster.minimum(:created_at)
      ].compact.min&.to_date || Date.today

      # Pagination for v2 data browsing
      @page = params[:page]&.to_i || 1
      @per_page = params[:per_page]&.to_i || 20
      @per_page = 100 if @per_page > 100 # Cap at 100

      if params[:view] == "v2_posters"
        begin
          relation = PyramidV2::Poster.all

          # Filter by status
          if params[:status].present? && %w[approved rejected].include?(params[:status])
            relation = relation.where(status: params[:status])
          end

          # Filter by date range
          if params[:start_date].present?
            relation = relation.where("created_at >= ?", params[:start_date])
          end
          if params[:end_date].present?
            relation = relation.where("created_at <= ?", params[:end_date])
          end

          # Sorting
          sort_column = params[:sort] || "created_at"
          sort_direction = params[:direction] == "asc" ? :asc : :desc
          allowed_sorts = %w[created_at status location_description]
          sort_column = "created_at" unless allowed_sorts.include?(sort_column)

          @v2_posters = relation
            .order(sort_column => sort_direction)
            .limit(@per_page)
            .offset((@page - 1) * @per_page)
          @total_count = relation.count
        rescue ActiveRecord::ConnectionNotEstablished, PG::ConnectionBad => e
          Rails.logger.warn "PyramidV2 database unavailable: #{e.message}"
          @v2_posters = []
          @total_count = 0
          flash.now[:alert] = "Historical data unavailable: PyramidV2 database not configured."
        end

      elsif params[:view] == "v2_referrals"
        begin
          relation = PyramidV2::ReferredSignUp.all

        # Filter by qualified status
        if params[:qualified].present?
          if params[:qualified] == "yes"
            relation = relation.where.not(qualified_detected_at: nil)
          elsif params[:qualified] == "no"
            relation = relation.where(qualified_detected_at: nil)
          end
        end

        # Filter by signup status
        if params[:signed_up].present?
          if params[:signed_up] == "yes"
            relation = relation.where.not(signup_detected_at: nil)
          elsif params[:signed_up] == "no"
            relation = relation.where(signup_detected_at: nil)
          end
        end

        # Filter by date range
        if params[:start_date].present?
          relation = relation.where("created_at >= ?", params[:start_date])
        end
        if params[:end_date].present?
          relation = relation.where("created_at <= ?", params[:end_date])
        end

        # Suspicious data filter (batch imports)
        if params[:suspicious] == "yes"
          relation = relation.where(
            "EXTRACT(SECOND FROM signup_detected_at) < 5 OR EXTRACT(SECOND FROM created_at) < 5"
          )
        end

        # Sorting
        sort_column = params[:sort] || "created_at"
        sort_direction = params[:direction] == "asc" ? :asc : :desc
        allowed_sorts = %w[created_at signup_detected_at qualified_detected_at email]
        sort_column = "created_at" unless allowed_sorts.include?(sort_column)

        @v2_referrals = relation
          .order(sort_column => sort_direction)
          .limit(@per_page)
          .offset((@page - 1) * @per_page)
        @total_count = relation.count
        rescue ActiveRecord::ConnectionNotEstablished, PG::ConnectionBad => e
          Rails.logger.warn "PyramidV2 database unavailable: #{e.message}"
          @v2_referrals = []
          @total_count = 0
          flash.now[:alert] = "Historical data unavailable: PyramidV2 database not configured."
        end
      end
    end

    def data
      v2_start_date = Date.new(2025, 6, 15)
      v3_start_date = [
        Referral.minimum(:created_at),
        Poster.minimum(:created_at)
      ].compact.min&.to_date || Date.today

      metric = params[:metric] || "referrals"
      max_days = 150 # About 5 months like v2

      # V2 campaign IDs
      athena_id = "vePHhmjo"
      summer_id = "vHvAQ8O4"

      # Try to get v2 data per campaign
      v2_athena = begin
        calculate_v2_cumulative_data_for_campaign(metric, v2_start_date, max_days, athena_id)
      rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid, PG::ConnectionBad, PG::UndefinedTable => e
        Rails.logger.warn "PyramidV2 database unavailable: #{e.message}"
        Array.new(max_days + 1, 0)
      end

      v2_summer = begin
        calculate_v2_cumulative_data_for_campaign(metric, v2_start_date, max_days, summer_id)
      rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid, PG::ConnectionBad, PG::UndefinedTable => e
        Array.new(max_days + 1, 0)
      end

      v3_data = calculate_v3_cumulative_data(metric, v3_start_date, max_days)

      render json: {
        v2_athena: v2_athena,
        v2_summer: v2_summer,
        v3: v3_data,
        labels: (0..max_days).to_a
      }
    end

    private

    def calculate_v2_cumulative_data_for_campaign(metric, start_date, max_days, campaign_id)
      case metric
      when "referrals"
        calculate_cumulative_by_day(
          PyramidV2::ReferredSignUp.where(campaign_id: campaign_id),
          :created_at,
          start_date,
          max_days
        )
      when "completed_referrals"
        calculate_cumulative_by_day(
          PyramidV2::ReferredSignUp.where(campaign_id: campaign_id).where.not(qualified_detected_at: nil),
          :qualified_detected_at,
          start_date,
          max_days
        )
      when "posters"
        calculate_cumulative_by_day(
          PyramidV2::Poster.where(campaign_id: campaign_id),
          :created_at,
          start_date,
          max_days
        )
      when "completed_posters"
        calculate_cumulative_by_day(
          PyramidV2::Poster.where(campaign_id: campaign_id).where(status: "approved"),
          :created_at,
          start_date,
          max_days
        )
      end
    end

    def calculate_v2_cumulative_data(metric, start_date, max_days)
      case metric
      when "referrals"
        calculate_cumulative_by_day(
          PyramidV2::ReferredSignUp,
          :created_at,
          start_date,
          max_days
        )
      when "completed_referrals"
        calculate_cumulative_by_day(
          PyramidV2::ReferredSignUp.where.not(qualified_detected_at: nil),
          :qualified_detected_at,
          start_date,
          max_days
        )
      when "posters"
        calculate_cumulative_by_day(
          PyramidV2::Poster,
          :created_at,
          start_date,
          max_days
        )
      when "completed_posters"
        calculate_cumulative_by_day(
          PyramidV2::Poster.where(status: "approved"),
          :created_at,
          start_date,
          max_days
        )
      end
    end

    def calculate_v3_cumulative_data(metric, start_date, max_days)
      case metric
      when "referrals"
        calculate_cumulative_by_day(
          Referral,
          :created_at,
          start_date,
          max_days
        )
      when "completed_referrals"
        calculate_cumulative_by_day(
          Referral.completed,
          :completed_at,
          start_date,
          max_days
        )
      when "posters"
        calculate_cumulative_by_day(
          Poster,
          :created_at,
          start_date,
          max_days
        )
      when "completed_posters"
        calculate_cumulative_by_day(
          Poster.verified,
          :verified_at,
          start_date,
          max_days
        )
      end
    end

    def calculate_cumulative_by_day(relation, date_field, start_date, max_days)
      # Whitelist allowed date fields for security
      allowed_date_fields = %i[created_at qualified_detected_at signup_detected_at completed_at verified_at]
      unless allowed_date_fields.include?(date_field.to_sym)
        Rails.logger.error "Invalid date_field: #{date_field}"
        return Array.new(max_days + 1, 0)
      end

      # Get counts by day using Arel for safe SQL generation
      table = relation.arel_table
      daily_counts = relation
        .where(table[date_field].gteq(start_date))
        .where(table[date_field].lt(start_date + (max_days + 1).days))
        .group(Arel.sql("DATE(#{relation.connection.quote_column_name(date_field)})"))
        .count

      # Convert to cumulative
      cumulative = []
      total = 0
      (0..max_days).each do |day|
        date = start_date + day.days
        total += daily_counts[date] || 0
        cumulative << total
      end

      cumulative
    rescue => e
      Rails.logger.error "Error calculating cumulative data: #{e.message}"
      Array.new(max_days + 1, 0)
    end
  end
end
