# frozen_string_literal: true

module Admin
  class PostersController < BaseController
    rescue_from ActiveRecord::RecordNotFound, with: :poster_not_found

    STATUSES = %w[all in_review pending success on_hold rejected digital].freeze

    def index
      @status = params[:status].presence_in(STATUSES) || "in_review"
      @search_query = params[:q].to_s.strip
      @user_filter = params[:user_id].presence
      @filtered_user = User.select(:id, :display_name, :email).find_by(id: @user_filter) if @user_filter.present?

      @posters = Poster.includes(:user, :campaign, :poster_group, proof_image_attachment: :blob)
      @posters = @posters.where(verification_status: @status) unless @status == "all"

      @posters = @posters.where(user_id: @user_filter) if @user_filter.present?

      if @search_query.present?
        escaped_query = ActiveRecord::Base.sanitize_sql_like(@search_query)
        search_term = "%#{escaped_query}%"
        @posters = @posters.joins("LEFT JOIN users ON users.id = posters.user_id")
                           .where(
                             <<~SQL.squish,
                               users.display_name ILIKE :search
                               OR users.email ILIKE :search
                               OR users.slack_id ILIKE :search
                               OR posters.referral_code ILIKE :search
                               OR posters.id::text = :exact
                             SQL
                             search: search_term,
                             exact: @search_query
                           )
      end

      @posters = @posters.order(Arel.sql("COALESCE(posters.verified_at, posters.created_at) DESC")).distinct
      @pagy, @posters = pagy(@posters)
    end

    def show
      @poster = Poster.includes(:user, :campaign, :poster_scans, :poster_group).find(params[:id])
      @scan_events = @poster.poster_scans.order(created_at: :desc).limit(25)
      @referral_logs = @poster.referral_code.present? ? ReferralCodeLog.for_code(@poster.referral_code).recent.limit(25) : []
    end

    def verify
      @poster = Poster.find(params[:id])
      @poster.verify!(current_user)
      redirect_to admin_posters_path, notice: "Poster verified and shards awarded."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_poster_path(@poster), alert: e.message
    end

    def hold
      @poster = Poster.find(params[:id])
      @poster.mark_on_hold!(params[:reason].presence)
      redirect_to admin_poster_path(@poster, status: params[:status].presence || @poster.verification_status.to_s.presence || "in_review"), notice: "Poster placed on hold."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_poster_path(@poster), alert: e.message
    end

    def reject
      @poster = Poster.find(params[:id])
      @poster.reject!(params[:reason], current_user)
      redirect_to admin_posters_path, notice: "Poster rejected."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_poster_path(@poster), alert: e.message
    end

    def mark_digital
      @poster = Poster.find(params[:id])
      if @poster.can_mark_digital?
        @poster.mark_digital!(current_user)
        redirect_to admin_posters_path(status: "digital"), notice: "Poster marked as digital (no shards awarded)."
      else
        redirect_to admin_poster_path(@poster), alert: "Cannot mark as digital: poster has proof submitted or is not in pending status."
      end
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_poster_path(@poster), alert: e.message
    end

    def retry_auto_verify
      @poster = Poster.find(params[:id])

      unless @poster.proof_image.attached?
        redirect_to admin_poster_path(@poster), alert: "Cannot retry: no proof image attached."
        return
      end

      # Use the auto-verification service
      result = PosterAutoVerificationService.new(@poster).call

      case result
      when :success
        redirect_to admin_posters_path(status: "success"), notice: "🎉 Poster auto-verified successfully! Shards awarded."
      else
        redirect_to admin_poster_path(@poster), notice: "Auto-verification attempted. Check metadata for results."
      end
    rescue => e
      Rails.logger.error "Retry auto-verify failed: #{e.message}"
      redirect_to admin_poster_path(@poster), alert: "Auto-verify failed: #{e.message}"
    end

    def request_resubmission
      @poster = Poster.find(params[:id])
      @poster.request_resubmission!(params[:reason].presence || "Please resubmit with clearer evidence", current_user)
      redirect_to admin_posters_path(status: params[:status].presence || "pending"), notice: "Poster sent back for resubmission."
    rescue => e
      redirect_to admin_poster_path(@poster), alert: "Failed to request resubmission: #{e.message}"
    end

    private

    def poster_not_found
      redirect_to admin_posters_path, alert: "Poster not found."
    end
  end
end
