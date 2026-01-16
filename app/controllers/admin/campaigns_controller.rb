# frozen_string_literal: true

module Admin
  class CampaignsController < BaseController
    def index
      @campaigns = Campaign.order(created_at: :desc)
      @shards_by_campaign = calculate_shards_by_campaign
      @api_keys_by_campaign = ApiKey.active.includes(:campaign).group_by(&:campaign_id)

      respond_to do |format|
        format.html
        format.text do
          render plain: @campaigns.map { |c|
            "#{c.name} (#{c.slug}) - #{c.active? ? 'Active' : 'Inactive'} - #{c.theme}"
          }.join("\n")
        end
      end
    end

    def show
      @campaign = Campaign.find(params[:id])
      @referral_stats = {
        total: @campaign.referrals.count,
        pending: @campaign.referrals.pending.count,
        verified: @campaign.referrals.id_verified.count,
        completed: @campaign.referrals.completed.count
      }
      @poster_stats = {
        total: @campaign.posters.count,
        pending: @campaign.posters.pending.count,
        verified: @campaign.posters.verified.count,
        rejected: @campaign.posters.rejected.count
      }
      @assets = @campaign.campaign_assets.group_by(&:asset_type)
      @airtable_sync_runs = @campaign.airtable_sync_runs.order(created_at: :desc).limit(5)
    end

    def new
      @campaign = Campaign.new(
        theme: "default",
        referral_shards: 3,
        poster_shards: 1,
        required_coding_minutes: 60
      )
    end

    def create
      @campaign = Campaign.new(campaign_params)

      if @campaign.save
        redirect_to admin_campaign_path(@campaign), notice: "Campaign created successfully."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @campaign = Campaign.find(params[:id])
    end

    def update
      @campaign = Campaign.find(params[:id])

      if @campaign.update(campaign_params)
        redirect_to admin_campaign_path(@campaign), notice: "Campaign updated successfully."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def calculate_shards_by_campaign
      result = {}

      # Shards from referrals (by campaign)
      referral_shards = ShardTransaction
        .where(transactable_type: "Referral")
        .joins("INNER JOIN referrals ON referrals.id = shard_transactions.transactable_id")
        .joins("INNER JOIN campaigns ON campaigns.id = referrals.campaign_id")
        .group("campaigns.name")
        .sum(:amount)

      referral_shards.each { |name, amount| result[name] = (result[name] || 0) + amount }

      # Shards from posters (by campaign)
      poster_shards = ShardTransaction
        .where(transactable_type: "Poster")
        .joins("INNER JOIN posters ON posters.id = shard_transactions.transactable_id")
        .joins("INNER JOIN campaigns ON campaigns.id = posters.campaign_id")
        .group("campaigns.name")
        .sum(:amount)

      poster_shards.each { |name, amount| result[name] = (result[name] || 0) + amount }

      # Admin grants and other transactions without campaign
      admin_shards = ShardTransaction
        .where(transactable_type: [ nil, "" ])
        .or(ShardTransaction.where.not(transactable_type: %w[Referral Poster]))
        .sum(:amount)

      result["Admin"] = admin_shards if admin_shards != 0

      result
    end

    def campaign_params
      params.require(:campaign).permit(
        :name, :slug, :theme, :description, :active, :status,
        :starts_at, :ends_at, :referral_shards, :poster_shards,
        :required_coding_minutes, :subdomain, :base_url, :custom_css,
        :airtable_base_id, :airtable_table_id, :airtable_sync_enabled,
        theme_config: {},
        i18n_overrides: {},
        airtable_field_mappings: {},
        poster_qr_coordinates: {}
      )
    end
  end
end
