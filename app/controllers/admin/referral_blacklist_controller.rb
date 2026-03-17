# frozen_string_literal: true

module Admin
  class ReferralBlacklistController < BaseController
    def index
      @entries = ReferralBlacklistEntry.order(created_at: :desc)

      if params[:q].present?
        escaped = ActiveRecord::Base.sanitize_sql_like(params[:q].strip)
        search_term = "%#{escaped}%"
        @entries = @entries.where(
          "referrer_identifier ILIKE :q OR referred_identifier ILIKE :q OR reason ILIKE :q",
          q: search_term
        )
      end

      @entries = @entries.where(active: params[:active] == "true") if params[:active].present?
      @entries = @entries.where(block_type: params[:block_type]) if params[:block_type].present?

      @pagy, @entries = pagy(@entries, limit: 25)
    end

    def new
      @entry = ReferralBlacklistEntry.new(block_type: params[:block_type] || "pair")
    end

    def create
      @entry = ReferralBlacklistEntry.new(entry_params)
      @entry.created_by = current_user

      if @entry.save
        redirect_to admin_referral_blacklist_index_path, notice: "Blacklist entry created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      @entry = ReferralBlacklistEntry.find(params[:id])
      @entry.deactivate!
      redirect_to admin_referral_blacklist_index_path, notice: "Blacklist entry deactivated."
    end

    def reactivate
      @entry = ReferralBlacklistEntry.find(params[:id])
      @entry.reactivate!
      redirect_to admin_referral_blacklist_index_path, notice: "Blacklist entry reactivated."
    end

    # Quick action to blacklist from user show page
    def quick_block_referrer
      user = User.find(params[:user_id])
      entry = ReferralBlacklistEntry.create!(
        block_type: "referrer",
        referrer_identifier: user.slack_id.presence || user.email,
        reason: params[:reason].presence || "Blocked by admin from user profile",
        created_by: current_user
      )
      redirect_back fallback_location: admin_user_path(user), notice: "All referrals by #{user.display_name} are now blocked."
    end

    private

    def entry_params
      attrs = params.require(:referral_blacklist_entry).permit(:block_type, :referrer_identifier, :referred_identifier, :custom_code, :reason)

      if attrs[:block_type] == "custom_code"
        attrs[:referrer_identifier] = attrs[:custom_code]
        attrs[:referred_identifier] = nil
      end

      attrs
    end
  end
end
