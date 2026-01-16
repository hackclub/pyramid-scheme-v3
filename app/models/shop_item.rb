# frozen_string_literal: true

class ShopItem < ApplicationRecord
  include Shop::Regionalizable

  has_many :shop_orders, dependent: :restrict_with_error, inverse_of: :shop_item

  validates :name, presence: true
  validates :price_shards, presence: true, numericality: { greater_than: 0 }
  validates :stock_quantity, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :sale_price_shards, numericality: { greater_than: 0, less_than_or_equal_to: :price_shards }, allow_nil: true, if: :on_sale?

  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :in_stock, -> { active.where("unlimited_stock = true OR stock_quantity > 0") }
  scope :out_of_stock, -> { active.where(unlimited_stock: false).where("stock_quantity <= 0 OR stock_quantity IS NULL") }
  scope :by_category, ->(category) { where(category: category) if category.present? }
  scope :on_sale, -> { where(on_sale: true) }
  scope :physical, -> { where(is_physical: true) }
  scope :digital, -> { where(is_physical: false) }
  scope :by_price, -> { order(price_shards: :asc) }

  def in_stock?
    unlimited_stock? || (stock_quantity.present? && stock_quantity.positive?)
  end

  def available_quantity
    return Float::INFINITY if unlimited_stock?
    stock_quantity || 0
  end

  def decrement_stock!(quantity = 1)
    return if unlimited_stock?

    update!(stock_quantity: [ stock_quantity - quantity, 0 ].max)
  end

  def user_can_purchase?(user, quantity = 1, price = nil)
    return false unless in_stock?

    # Use provided price (with regional adjustments) or fall back to current_price
    price = price || current_price
    return false unless user.can_afford?(price * quantity)
    return false if !unlimited_stock? && stock_quantity < quantity
    return false if max_per_user && user_purchase_count(user) + quantity > max_per_user

    true
  end

  def user_purchase_count(user)
    shop_orders.where(user: user).where.not(status: "cancelled").sum(:quantity)
  end

  def max_quantity_per_order
    return nil if !is_physical  # Unlimited for digital/grant items
    10  # Max 10 for physical items
  end

  def physical?
    is_physical
  end

  def current_price
    on_sale? && sale_price_shards.present? ? sale_price_shards : price_shards
  end

  def savings_percentage(region_code = nil)
    return 0 unless on_sale? && sale_price_shards.present?

    if region_code
      original = original_price_for_region(region_code)
      sale = price_for_region(region_code)
      ((original - sale).to_f / original * 100).round
    else
      ((price_shards - sale_price_shards).to_f / price_shards * 100).round
    end
  end

  def original_price_for_region(region_code)
    region_code = region_code.to_s.upcase
    region_code = "XX" unless Shop::Regionalizable::REGION_CODES.include?(region_code)

    # Get region-specific offset
    region_offset = send("price_offset_#{region_code.downcase}")
    offset = region_offset.present? ? region_offset : (send("price_offset_xx") || 0)

    (price_shards + offset).to_i
  end
end
