# frozen_string_literal: true

require "test_helper"

class ShopItemTest < ActiveSupport::TestCase
  setup do
    @stickers = shop_items(:stickers)
    @smolhaj = shop_items(:smolhaj)
    @out_of_stock = shop_items(:out_of_stock_item)
    @inactive = shop_items(:inactive_item)
  end

  test "unlimited_stock item is always in stock" do
    assert @stickers.unlimited_stock?
    # Unlimited stock items should not have a stock_quantity limit
  end

  test "limited stock item tracks quantity" do
    assert_not @smolhaj.unlimited_stock?
    assert @smolhaj.stock_quantity.positive?
  end

  test "out of stock item has zero quantity" do
    assert_equal 0, @out_of_stock.stock_quantity
  end

  test "inactive item is not visible to users" do
    assert_not @inactive.active?
  end
end
