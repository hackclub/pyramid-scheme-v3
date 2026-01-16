# frozen_string_literal: true

class VideoSubmissionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_submission, only: [ :destroy, :request_virality_check ]
  before_action :check_rate_limit, only: [ :create ]

  def create
    @campaign = Campaign.find_by!(slug: params[:campaign_slug])
    @submission = current_user.video_submissions.build(submission_params)
    @submission.campaign = @campaign

    if @submission.save
      redirect_to campaign_path(@campaign.slug), notice: "Video submission received! It will be reviewed soon."
    else
      redirect_to campaign_path(@campaign.slug), alert: @submission.errors.full_messages.join(", ")
    end
  end

  def destroy
    unless @submission.can_delete?
      redirect_to campaign_path(@submission.campaign.slug), alert: "Cannot delete a submission that is not pending."
      return
    end

    @submission.destroy
    redirect_to campaign_path(@submission.campaign.slug), notice: "Submission deleted."
  end

  def request_virality_check
    unless @submission.can_check_virality?
      if request.turbo_frame_request?
        render turbo_stream: turbo_stream.replace("virality_check_#{@submission.id}", partial: "video_submissions/virality_check", locals: { submission: @submission, error: "Cannot request virality check for this submission." })
      else
        redirect_to campaign_path(@submission.campaign.slug), alert: "Cannot request virality check for this submission."
      end
      return
    end

    @submission.update!(metadata: @submission.metadata.merge(virality_check_requested: true, virality_check_requested_at: Time.current.iso8601))

    if request.turbo_frame_request?
      render turbo_stream: turbo_stream.replace("virality_check_#{@submission.id}", partial: "video_submissions/virality_check", locals: { submission: @submission })
    else
      redirect_to campaign_path(@submission.campaign.slug), notice: "Virality check requested!"
    end
  end

  private

  def set_submission
    @submission = current_user.video_submissions.find(params[:id])
  end

  def submission_params
    params.require(:video_submission).permit(:video_url, video_files: [])
  end

  def check_rate_limit
    return if current_user.admin?

    @campaign = Campaign.find_by!(slug: params[:campaign_slug])
    recent_count = current_user.video_submissions
      .for_campaign(@campaign)
      .where("created_at > ?", 1.hour.ago)
      .count

    if recent_count >= 2
      redirect_to campaign_path(@campaign.slug), alert: "You can only submit videos twice per hour. Please try again later."
    end
  end
end
