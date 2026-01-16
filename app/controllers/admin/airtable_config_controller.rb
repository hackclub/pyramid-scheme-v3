# frozen_string_literal: true

module Admin
  class AirtableConfigController < BaseController
    before_action :set_campaign, only: [ :show, :update, :sync, :test_connection ]

    # GET /admin/airtable_config
    def index
      @campaigns = Campaign.order(:name)
      @airtable_bases = fetch_airtable_bases
    end

    # GET /admin/airtable_config/:campaign_id
    def show
      @airtable_bases = fetch_airtable_bases
      @base_tables = @campaign.airtable_base_id.present? ? fetch_base_tables(@campaign.airtable_base_id) : []
    end

    # PATCH /admin/airtable_config/:campaign_id
    def update
      if @campaign.update(airtable_params)
        redirect_to admin_airtable_config_path(@campaign), notice: "Airtable configuration updated."
      else
        @airtable_bases = fetch_airtable_bases
        @base_tables = @campaign.airtable_base_id.present? ? fetch_base_tables(@campaign.airtable_base_id) : []
        render :show, status: :unprocessable_entity
      end
    end

    # POST /admin/airtable_config/:campaign_id/sync
    def sync
      begin
        service = AirtableSyncService.new(campaign: @campaign)
        stats = service.perform

        if stats[:errors].any?
          redirect_to admin_airtable_config_path(@campaign), alert: "Sync completed with errors: #{stats[:errors].join(', ')}"
        else
          redirect_to admin_airtable_config_path(@campaign), notice: "Sync completed: #{stats[:users_synced]} synced, #{stats[:users_skipped]} skipped."
        end
      rescue => e
        redirect_to admin_airtable_config_path(@campaign), alert: "Sync failed: #{e.message}"
      end
    end

    # POST /admin/airtable_config/:campaign_id/test_connection
    def test_connection
      begin
        api = AirtableApiService.new

        if @campaign.airtable_base_id.present?
          tables = api.get_base_schema(@campaign.airtable_base_id)
          render json: { success: true, tables: tables }
        else
          render json: { success: false, error: "No base ID configured" }
        end
      rescue AirtableApiService::ApiError => e
        render json: { success: false, error: e.message }
      end
    end

    # GET /admin/airtable_config/bases
    def bases
      @bases = fetch_airtable_bases
      render json: @bases
    end

    # GET /admin/airtable_config/bases/:base_id/tables
    def tables
      @tables = fetch_base_tables(params[:base_id])
      render json: @tables
    end

    private

    def set_campaign
      @campaign = Campaign.find(params[:campaign_id])
    end

    def airtable_params
      params.require(:campaign).permit(
        :airtable_base_id,
        :airtable_table_id,
        :airtable_sync_enabled,
        airtable_field_mappings: {}
      )
    end

    def fetch_airtable_bases
      AirtableApiService.new.list_bases
    rescue AirtableApiService::ApiError => e
      Rails.logger.error "Failed to fetch Airtable bases: #{e.message}"
      []
    end

    def fetch_base_tables(base_id)
      return [] unless base_id.present?
      AirtableApiService.new.get_base_schema(base_id)
    rescue AirtableApiService::ApiError => e
      Rails.logger.error "Failed to fetch tables for base #{base_id}: #{e.message}"
      []
    end
  end
end
