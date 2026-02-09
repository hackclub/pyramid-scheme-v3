# frozen_string_literal: true

module Admin
  class ReferralsController < BaseController
    def index
      @search_query = params[:q].to_s.strip
      @status_filter = normalized_status_filter(params[:status])

      @referrals = Referral.includes(:referrer, :referred, :campaign)
                           .order(Arel.sql("COALESCE(completed_at, verified_at, created_at) DESC"))

      # Filter by status
      if @status_filter.present? && @status_filter != "all"
        @referrals = @referrals.where(status: @status_filter)
      end

      # Filter by campaign
      if params[:campaign_id].present?
        @referrals = @referrals.where(campaign_id: params[:campaign_id])
      end

      # Filter by referral type
      if params[:referral_type].present? && params[:referral_type] != "all"
        @referrals = @referrals.where(referral_type: params[:referral_type])
      end

      # Filter by poster subtype (digital vs manual)
      if params[:poster_subtype].present? && params[:poster_subtype] != "all"
        if params[:poster_subtype] == "digital"
          @referrals = @referrals
            .where(referral_type: "poster")
            .where(
              "EXISTS (SELECT 1 FROM posters WHERE posters.user_id = referrals.referrer_id AND posters.verification_status = ?)",
              "digital"
            )
        elsif params[:poster_subtype] == "manual"
          @referrals = @referrals
            .where(referral_type: "poster")
            .where(
              "NOT EXISTS (SELECT 1 FROM posters WHERE posters.user_id = referrals.referrer_id AND posters.verification_status = ?)",
              "digital"
            )
        end
      end

      # Search across referral + user identity fields
      if @search_query.present?
        escaped_query = ActiveRecord::Base.sanitize_sql_like(@search_query)
        search_term = "%#{escaped_query}%"
        @referrals = @referrals.joins("LEFT JOIN users AS referrer_users ON referrer_users.id = referrals.referrer_id")
                               .joins("LEFT JOIN users AS referred_users ON referred_users.id = referrals.referred_id")
                               .where(
                                 <<~SQL.squish,
                                   referrer_users.display_name ILIKE :search
                                   OR referrer_users.email ILIKE :search
                                   OR referrer_users.slack_id ILIKE :search
                                   OR referrer_users.referral_code ILIKE :search
                                   OR referrer_users.custom_referral_code ILIKE :search
                                   OR referred_users.display_name ILIKE :search
                                   OR referred_users.email ILIKE :search
                                   OR referred_users.slack_id ILIKE :search
                                   OR referrals.referred_identifier ILIKE :search
                                   OR COALESCE(referrals.metadata->>'censored_email', '') ILIKE :search
                                   OR referrals.id::text = :exact
                                 SQL
                                 search: search_term,
                                 exact: @search_query
                               )
      end

      @referrals = @referrals.distinct
      @pagy, @referrals = pagy(@referrals, limit: 25)
      @campaigns = Campaign.order(name: :asc)

      # Preload poster verification statuses for poster-type referrals to avoid N+1
      poster_referrer_ids = @referrals.select { |r| r.referral_type == "poster" }.map(&:referrer_id)
      @poster_statuses_by_user = if poster_referrer_ids.any?
        Poster.where(user_id: poster_referrer_ids)
              .pluck(:user_id, :verification_status)
              .to_h
      else
        {}
      end

      # Stats for dashboard cards - single query instead of 4 separate counts
      status_counts = Referral.group(:status).count
      @stats = {
        total: status_counts.values.sum,
        pending: status_counts["pending"] || 0,
        id_verified: status_counts["id_verified"] || 0,
        completed: status_counts["completed"] || 0
      }
    end

    def show
      @referral = Referral.includes(:referrer, :referred, :campaign).find(params[:id])
    end

    def verify
      @referral = Referral.find(params[:id])
      @referral.verify_identity!
      redirect_to admin_referral_path(@referral), notice: "Referral verified successfully"
    rescue => e
      redirect_to admin_referral_path(@referral), alert: "Error verifying referral: #{e.message}"
    end

    def complete
      @referral = Referral.find(params[:id])
      @referral.complete!
      redirect_to admin_referral_path(@referral), notice: "Referral completed successfully"
    rescue => e
      redirect_to admin_referral_path(@referral), alert: "Error completing referral: #{e.message}"
    end

    def update_minutes
      @referral = Referral.find(params[:id])
      minutes = params[:referral][:tracked_minutes].to_i
      @referral.update_tracked_time!(minutes)
      redirect_to admin_referral_path(@referral), notice: "Tracked minutes updated to #{minutes}"
    rescue => e
      redirect_to admin_referral_path(@referral), alert: "Error updating minutes: #{e.message}"
    end

    def destroy
      @referral = Referral.find(params[:id])
      referrer = @referral.referrer
      campaign = @referral.campaign
      was_completed = @referral.completed?

      # If the referral was completed, try to deduct shards (but not below 0)
      if was_completed
        shards_to_deduct = campaign.referral_shards
        actual_deduction = [ shards_to_deduct, referrer.total_shards ].min

        if actual_deduction > 0
          referrer.credit_shards!(
            -actual_deduction,
            transaction_type: "admin_debit",
            transactable: nil,
            description: "Referral ##{@referral.id} deleted by admin (originally for #{@referral.referred_identifier})"
          )
        end
      end

      @referral.destroy!

      # Update referrer's referral count
      referrer.update!(referral_count: referrer.referrals_given.completed.count)

      redirect_to admin_referrals_path, notice: "Referral deleted successfully#{was_completed ? " and #{[ campaign.referral_shards, referrer.total_shards + [ campaign.referral_shards, referrer.total_shards ].min ].min} shards deducted from #{referrer.display_name}" : ''}"
    rescue => e
      redirect_to admin_referral_path(@referral), alert: "Error deleting referral: #{e.message}"
    end

    private

    def normalized_status_filter(raw_status)
      status = raw_status.to_s.strip
      return "all" if status.blank? || status == "all"
      return status if Referral.statuses.key?(status)

      Referral.statuses.key(status.to_i)
    end
  end
end
