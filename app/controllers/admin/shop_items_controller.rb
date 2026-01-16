# frozen_string_literal: true

module Admin
  class ShopItemsController < BaseController
    def index
      @shop_items = ShopItem.order(created_at: :desc)

      respond_to do |format|
        format.html
        format.text do
          render plain: @shop_items.map { |item|
            stock = item.unlimited_stock? ? "Unlimited" : item.stock_quantity.to_s
            "#{item.name} | #{item.price_shards} shards | Stock: #{stock} | #{item.active? ? 'Active' : 'Inactive'}"
          }.join("\n")
        end
      end
    end

    def new
      @shop_item = ShopItem.new
    end

    def create
      @shop_item = ShopItem.new(shop_item_params)

      if @shop_item.save
        redirect_to admin_shop_items_path, notice: "Shop item created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @shop_item = ShopItem.find(params[:id])
    end

    def update
      @shop_item = ShopItem.find(params[:id])

      if @shop_item.update(shop_item_params)
        redirect_to admin_shop_items_path, notice: "Shop item updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @shop_item = ShopItem.find(params[:id])

      if @shop_item.shop_orders.any?
        redirect_to admin_shop_items_path, alert: "Cannot delete item with existing orders."
      else
        @shop_item.destroy
        redirect_to admin_shop_items_path, notice: "Shop item deleted."
      end
    end

    private

    def shop_item_params
      params.require(:shop_item).permit(
        :name, :description, :price_shards, :stock_quantity,
        :unlimited_stock, :active, :image_url, :category, :max_per_user,
        :on_sale, :sale_price_shards
      )
    end
  end
end
