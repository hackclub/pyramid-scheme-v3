# frozen_string_literal: true

class ShopOrdersController < ApplicationController
  include Regionable

  def index
    @pagy, @orders = pagy(current_user.shop_orders.includes(:shop_item).recent)
  end

  def show
    @order = current_user.shop_orders.includes(:shop_item).find(params[:id])
  end

  def create
    @item = ShopItem.find(params[:shop_item_id])
    quantity = (params[:quantity] || 1).to_i
    shipping_address = params.dig(:shop_order, :shipping_address)

    # Validate quantity
    if quantity < 1
      flash[:alert] = "Quantity must be at least 1."
      return redirect_to shop_item_path(@item)
    end

    max_qty = @item.max_quantity_per_order
    if max_qty && quantity > max_qty
      flash[:alert] = "Maximum quantity per order is #{max_qty}."
      return redirect_to shop_item_path(@item)
    end

    if shipping_address.blank?
      flash[:alert] = "Please select a shipping address."
      return redirect_to shop_item_path(@item)
    end

    # Use current_price (accounts for sales, no regional pricing complexity)
    item_price = @item.current_price

    unless @item.user_can_purchase?(current_user, quantity, item_price)
      Rails.logger.warn("[ShopOrder] Purchase blocked for user #{current_user.id}: " \
        "item=#{@item.id} (#{@item.name}), qty=#{quantity}, " \
        "item_price=#{item_price}, user_shards=#{current_user.total_shards}, " \
        "on_sale=#{@item.on_sale?}, sale_price=#{@item.sale_price_shards}, " \
        "base_price=#{@item.price_shards}, current_price=#{@item.current_price}")

      flash[:alert] = if !current_user.can_afford?(item_price * quantity)
        "You don't have enough shards for this purchase."
      elsif !@item.in_stock?
        "This item is out of stock."
      else
        "You cannot purchase this item."
      end
      return redirect_to shop_item_path(@item)
    end

    ActiveRecord::Base.transaction do
      order = ShopOrder.create!(
        user: current_user,
        shop_item: @item,
        quantity: quantity,
        status: "pending",
        total_shards: item_price * quantity,
        shipping_address: shipping_address
      )

      current_user.debit_shards!(
        order.total_shards,
        transaction_type: "purchase",
        transactable: order,
        description: "Purchase: #{@item.name} x#{quantity}"
      )

      redirect_to shop_order_path(order), notice: "Order placed successfully!"
    end
  rescue User::InsufficientShardsError
    redirect_to shop_item_path(@item), alert: "You don't have enough shards for this purchase."
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("Shop order creation failed: #{e.message}")
    Rails.logger.error(e.record.errors.full_messages.join(", ")) if e.record
    redirect_to shop_item_path(@item), alert: "Unable to create order: #{e.record&.errors&.full_messages&.to_sentence || e.message}"
  rescue StandardError => e
    Rails.logger.error("Unexpected error creating shop order: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.first(10).join("\n"))
    redirect_to shop_item_path(@item), alert: "An unexpected error occurred. Please try again or contact support."
  end
end
