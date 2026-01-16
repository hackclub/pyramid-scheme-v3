# frozen_string_literal: true

module Admin
  class ApiKeysController < BaseController
    def index
      @api_keys = ApiKey.includes(:campaign).order(created_at: :desc)
    end

    def new
      @api_key = ApiKey.new
      @campaigns = Campaign.all
    end

    def create
      @api_key = ApiKey.new(api_key_params)

      if @api_key.save
        flash[:raw_key] = @api_key.raw_key
        redirect_to admin_api_keys_path, notice: t("admin.api_keys.flash.created")
      else
        @campaigns = Campaign.all
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      @api_key = ApiKey.find(params[:id])
      @api_key.deactivate!
      redirect_to admin_api_keys_path, notice: t("admin.api_keys.flash.deactivated")
    end

    private

    def api_key_params
      params.require(:api_key).permit(:name, :campaign_id, :description, permissions: {})
    end
  end
end
