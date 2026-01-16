# frozen_string_literal: true

module Admin
  class DashboardController < BaseController
    def index
      @total_users = User.count
      @total_referrals = Referral.count
      @completed_referrals = Referral.completed.count
      @total_posters = Poster.count
      @verified_posters = Poster.verified.count
      @pending_orders = ShopOrder.pending.count
      @total_shards_awarded = ShardTransaction.sum(:amount) || 0

      # Poster referral metrics
      @poster_referrals = Referral.from_posters.count
      @poster_referrals_completed = Referral.from_posters.completed.count
      @poster_referrals_digital = Referral.from_posters.joins("INNER JOIN posters ON posters.referral_code = (SELECT referral_code FROM posters WHERE posters.user_id = referrals.referrer_id AND referrals.referral_type = 'poster' LIMIT 1)").where("posters.verification_status = 'digital'").count
      @link_referrals = Referral.from_links.count
      @link_referrals_completed = Referral.from_links.completed.count
      @total_poster_scans = PosterScan.count

      # Calculate hours directly from Airtable based on referral completion status
      # Completed referrals hours (verified)
      completed_referral_emails = Referral.completed.pluck(:referred_identifier).map(&:downcase)
      @verified_hours = AirtableReferral.where("LOWER(email) IN (?)", completed_referral_emails).sum("COALESCE((metadata->>'hours')::numeric, 0)") || 0

      # Incomplete referrals hours (pending + id_verified)
      incomplete_referral_emails = Referral.where.not(status: :completed).pluck(:referred_identifier).map(&:downcase)
      @unverified_hours = AirtableReferral.where("LOWER(email) IN (?)", incomplete_referral_emails).sum("COALESCE((metadata->>'hours')::numeric, 0)") || 0

      # Total hours (completed + incomplete)
      @total_hours = @verified_hours + @unverified_hours

      @recent_users = User.order(created_at: :desc).limit(10)
      @recent_referrals = Referral.includes(:referrer, :campaign).order(created_at: :desc).limit(10)
      @pending_posters = Poster.pending.includes(:user, :campaign).limit(10)
      @airtable_sync_runs = AirtableSyncRun.order(started_at: :desc, created_at: :desc).limit(10)

      if params[:referral_code].present?
        @referral_lookup_code = params[:referral_code].to_s.strip.upcase
        @referral_lookup_result = lookup_user_by_referral_code(@referral_lookup_code)
      end
    end

    private

    def lookup_user_by_referral_code(code)
      return { error: "Enter a referral code" } if code.blank?

      if (user = User.find_by_any_referral_code(code))
        source = user.custom_referral_code&.casecmp?(code) ? :custom_link : :user
        { user: user, source: source }
      elsif (poster = Poster.includes(:user, :campaign).find_by(referral_code: code.upcase))
        { user: poster.user, source: :poster, poster: poster }
      else
        { error: "No user found for referral code #{code}" }
      end
    end
  end
end
