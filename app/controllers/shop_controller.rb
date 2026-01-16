# frozen_string_literal: true

class ShopController < ApplicationController
  include Regionable

  before_action :set_user_region

  def index
    @items = ShopItem.in_stock.where.not(name: "Hack Club T-Shirt").order(:price_shards)
    @category = params[:category]
    @items = @items.by_category(@category) if @category.present?

    # No region-based filtering - show all items with regional pricing

    @region_options = Shop::Regionalizable::REGIONS.map do |code, config|
      { label: config[:name], value: code }
    end
  end

  def update_region
    region = params[:region]&.upcase
    unless Shop::Regionalizable::REGION_CODES.include?(region)
      return head :unprocessable_entity
    end

    current_user.update!(region: region)
    redirect_to shop_path, notice: "Region updated to #{Shop::Regionalizable::REGIONS.dig(region, :name)}"
  end

  private

  def set_user_region
    @user_region = determine_user_region
  end

  public

  def show
    @item = ShopItem.find(params[:id])
    redirect_to shop_path, alert: "That item isn't available right now." if @item.name == "Hack Club T-Shirt"

    # Set user region for pricing display
    @user_region = determine_user_region
  end
end
