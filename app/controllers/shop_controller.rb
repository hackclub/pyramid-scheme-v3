# frozen_string_literal: true

class ShopController < ApplicationController
  include Regionable

  SORT_OPTIONS = %w[price_asc price_desc].freeze

  before_action :set_user_region

  def index
    @sort = params[:sort].presence_in(SORT_OPTIONS) || "price_asc"
    @items = ShopItem.in_stock.where.not(name: "Hack Club T-Shirt")
    @category = params[:category]
    @items = @items.by_category(@category) if @category.present?
    @items = sort_items(@items)

    # No region-based filtering - show all items with regional pricing

    @region_options = Shop::Regionalizable::REGIONS.map do |code, config|
      { label: config[:name], value: code }
    end
    @sort_options = [
      [ "Price: Low to High", "price_asc" ],
      [ "Price: High to Low", "price_desc" ]
    ]
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

  def sort_items(scope)
    effective_price_sql = <<~SQL.squish
      CASE
        WHEN on_sale = TRUE AND sale_price_shards IS NOT NULL THEN sale_price_shards
        ELSE price_shards
      END
    SQL

    case @sort
    when "price_desc"
      scope.order(Arel.sql("#{effective_price_sql} DESC, name ASC"))
    else
      scope.order(Arel.sql("#{effective_price_sql} ASC, name ASC"))
    end
  end

  public

  def show
    @item = ShopItem.find(params[:id])
    redirect_to shop_path, alert: "That item isn't available right now." if @item.name == "Hack Club T-Shirt"

    # Set user region for pricing display
    @user_region = determine_user_region
  end
end
