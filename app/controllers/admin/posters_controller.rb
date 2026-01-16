# frozen_string_literal: true

module Admin
  class PostersController < BaseController
    rescue_from ActiveRecord::RecordNotFound, with: :poster_not_found

    STATUSES = %w[in_review pending success on_hold rejected digital].freeze

    def index
      @status = params[:status].presence_in(STATUSES) || "in_review"
      @posters = Poster.includes(:user, :campaign, :poster_group, proof_image_attachment: :blob).where(verification_status: @status).order(created_at: :desc)
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
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_poster_path(@poster), alert: e.message
    end

    private

    def poster_not_found
      redirect_to admin_posters_path, alert: "Poster not found."
    end
  end
end
