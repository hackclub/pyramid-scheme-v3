# frozen_string_literal: true

class CampaignsController < ApplicationController
  before_action :check_campaign_access, only: [ :show ]

  def index
    # Always redirect to Flavortown if it exists and is open
    flavortown = Campaign.flavortown
    if flavortown.present? && flavortown.open?
      return redirect_to campaign_path(flavortown.slug)
    end

    # Fallback: redirect to root if no campaigns available
    redirect_to root_path
  end

  def show
    @campaign = Campaign.find_by!(slug: params[:slug])
    @campaign_logic = BaseCampaignLogic.for(@campaign)

    @user = current_user
    @poster = current_user.posters.build(campaign: @campaign)

    # Eager load associations to prevent N+1 queries
    @user_referrals = @user.referrals_given
      .for_campaign(@campaign)
      .includes(:referred, :campaign)
      .order(created_at: :desc)

    @user_posters = @user.posters
      .for_campaign(@campaign)
      .standalone
      .includes(:campaign, :poster_scans)
      .order(created_at: :desc)

    @user_poster_groups = @user.poster_groups
      .for_campaign(@campaign)
      .includes(:posters, :campaign)
      .recent

    @user_referral_received = @user.referrals_received
      .for_campaign(@campaign)
      .includes(:referrer)
      .first

    @referral_link = @campaign_logic.referral_url_for(current_user.effective_referral_code)

    # Leaderboards - these are optimized queries with aggregation
    @top_referrers = @campaign.leaderboard_referrals.limit(10)
    @top_posters = @campaign.leaderboard_posters.limit(10)
  end

  private

  def check_campaign_access
    @campaign = Campaign.find_by!(slug: params[:slug])

    # Closed campaigns are not accessible
    if @campaign.closed?
      redirect_to campaigns_path, alert: t("campaigns.errors.closed")
      return
    end

    # Coming soon campaigns are only accessible to admins
    if @campaign.coming_soon? && !current_user&.admin?
      redirect_to root_path, alert: t("campaigns.errors.coming_soon")
      nil
    end
  end
end
