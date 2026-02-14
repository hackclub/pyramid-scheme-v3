# frozen_string_literal: true

require "test_helper"

class ShopOrderTest < ActiveSupport::TestCase
  setup do
    @user = users(:regular_user)
    @shop_item = shop_items(:stickers)
  end

  test "cancel! refunds approved orders" do
    order = ShopOrder.create!(
      user: @user,
      shop_item: @shop_item,
      quantity: 2,
      total_shards: 6,
      status: "approved"
    )
    starting_shards = @user.total_shards

    order.cancel!

    assert_equal "cancelled", order.reload.status
    assert_equal starting_shards + 6, @user.reload.total_shards
  end

  test "unapprove! transitions approved order to in_review" do
    order = ShopOrder.create!(
      user: @user,
      shop_item: @shop_item,
      quantity: 1,
      total_shards: 3,
      status: "approved"
    )

    order.unapprove!

    assert_equal "in_review", order.reload.status
  end

  test "unapprove! raises unless order is approved" do
    order = ShopOrder.create!(
      user: @user,
      shop_item: @shop_item,
      quantity: 1,
      total_shards: 3,
      status: "pending"
    )

    error = assert_raises(StandardError) { order.unapprove! }
    assert_includes error.message, "Only approved orders can be unapproved"
  end
end
