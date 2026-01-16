# frozen_string_literal: true

module Admin
  class VideoSubmissionsController < BaseController
    rescue_from ActiveRecord::RecordNotFound, with: :submission_not_found

    STATUSES = %w[pending on_hold approved rejected].freeze

    def index
      @status = params[:status].presence_in(STATUSES) || "pending"
      @submissions = VideoSubmission.includes(:user, :campaign, video_files_attachments: :blob)
        .where(status: @status)
        .order(created_at: :desc)
      @pagy, @submissions = pagy(@submissions)
    end

    def show
      @submission = VideoSubmission.includes(:user, :campaign, :reviewed_by, :virality_checked_by, video_files_attachments: :blob).find(params[:id])
    end

    def approve
      @submission = VideoSubmission.find(params[:id])
      shards = params[:shards].to_i.clamp(1, 10)

      @submission.approve!(current_user, shards: shards)
      redirect_to admin_video_submissions_path, notice: "Video approved! #{shards} shards awarded."
    rescue ArgumentError => e
      redirect_to admin_video_submission_path(@submission), alert: e.message
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_video_submission_path(@submission), alert: e.message
    end

    def hold
      @submission = VideoSubmission.find(params[:id])
      @submission.hold!(current_user, notes: params[:notes].presence)
      redirect_to admin_video_submission_path(@submission), notice: "Video placed on hold."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_video_submission_path(@submission), alert: e.message
    end

    def reject
      @submission = VideoSubmission.find(params[:id])
      @submission.reject!(current_user, notes: params[:notes].presence)
      redirect_to admin_video_submissions_path, notice: "Video rejected."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_video_submission_path(@submission), alert: e.message
    end

    def complete_virality
      @submission = VideoSubmission.find(params[:id])
      is_viral = params[:is_viral] == "true"
      bonus = params[:bonus].to_i.clamp(0, 20)

      @submission.complete_virality_check!(current_user, is_viral: is_viral, bonus: bonus)
      redirect_to admin_video_submission_path(@submission), notice: "Virality check completed.#{is_viral ? " #{bonus} bonus shards awarded!" : ""}"
    rescue ArgumentError => e
      redirect_to admin_video_submission_path(@submission), alert: e.message
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_video_submission_path(@submission), alert: e.message
    end

    private

    def submission_not_found
      redirect_to admin_video_submissions_path, alert: "Video submission not found."
    end
  end
end
