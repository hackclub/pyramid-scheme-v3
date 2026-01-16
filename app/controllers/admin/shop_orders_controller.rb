# frozen_string_literal: true

module Admin
  class ShopOrdersController < BaseController
    STATUSES = %w[pending in_review on_hold approved fulfilled cancelled].freeze

    def index
      @status = params[:status].presence_in(STATUSES) || "pending"
      @orders = ShopOrder.includes(:user, :shop_item).where(status: @status).order(created_at: :desc)
      @pagy, @orders = pagy(@orders)
    end

    def show
      @order = ShopOrder.includes(:user, :shop_item, :fulfilled_by).find(params[:id])
    end

    def approve
      @order = ShopOrder.find(params[:id])
      @order.approve!
      redirect_to admin_shop_orders_path, notice: "Order approved."
    end

    def fulfill
      @order = ShopOrder.find(params[:id])
      @order.fulfill!(current_user)
      redirect_to admin_shop_orders_path, notice: "Order fulfilled."
    end

    def cancel
      @order = ShopOrder.find(params[:id])
      @order.cancel!
      redirect_to admin_shop_orders_path, notice: "Order cancelled and refunded."
    end

    def mark_in_review
      @order = ShopOrder.find(params[:id])
      @order.mark_in_review!
      redirect_to admin_shop_order_path(@order), notice: "Order marked for review."
    end

    def mark_on_hold
      @order = ShopOrder.find(params[:id])
      @order.mark_on_hold!
      redirect_to admin_shop_order_path(@order), notice: "Order put on hold."
    end

    def update_notes
      @order = ShopOrder.find(params[:id])
      @order.update!(admin_notes: params[:admin_notes])
      redirect_to admin_shop_order_path(@order), notice: "Notes updated."
    end
  end
end
