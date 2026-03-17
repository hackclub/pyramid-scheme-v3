# frozen_string_literal: true

module Api
  module V1
    class DashboardStatsController < BaseController
      before_action -> { require_permission!(:referrals, :read) }
      before_action :require_flavortown_campaign!

      def show
        render_success(CampaignDashboardStatsService.new(campaign: current_campaign).call)
      end

      private

      def require_flavortown_campaign!
        return if current_campaign&.slug == "flavortown"

        render_error("Dashboard stats are only available for the Flavortown campaign", status: :forbidden)
      end
    end
  end
end
