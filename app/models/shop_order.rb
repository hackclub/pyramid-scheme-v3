# frozen_string_literal: true

class ShopOrder < ApplicationRecord
  STATUSES = %w[pending in_review on_hold approved fulfilled cancelled].freeze

  belongs_to :user, inverse_of: :shop_orders
  belongs_to :shop_item, inverse_of: :shop_orders
  belongs_to :fulfilled_by, class_name: "User", optional: true

  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :total_shards, presence: true, numericality: { greater_than: 0 }
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: "pending") }
  scope :in_review, -> { where(status: "in_review") }
  scope :on_hold, -> { where(status: "on_hold") }
  scope :approved, -> { where(status: "approved") }
  scope :fulfilled, -> { where(status: "fulfilled") }
  scope :cancelled, -> { where(status: "cancelled") }
  scope :active, -> { where(status: %w[pending in_review on_hold approved]) }
  scope :recent, -> { order(created_at: :desc) }
  scope :with_user, -> { includes(:user) }
  scope :with_item, -> { includes(:shop_item) }
  scope :with_associations, -> { includes(:user, :shop_item) }

  def status_label
    {
      "pending" => "Pending",
      "in_review" => "In Review",
      "on_hold" => "On Hold",
      "approved" => "Approved",
      "fulfilled" => "Shipped",
      "cancelled" => "Cancelled"
    }[status] || status.titleize
  end

  def status_color
    {
      "pending" => "bg-yellow-500/10 text-yellow-500 border-yellow-500/20",
      "in_review" => "bg-blue-500/10 text-blue-500 border-blue-500/20",
      "on_hold" => "bg-orange-500/10 text-orange-500 border-orange-500/20",
      "approved" => "bg-green-500/10 text-green-500 border-green-500/20",
      "fulfilled" => "bg-emerald-500/10 text-emerald-500 border-emerald-500/20",
      "cancelled" => "bg-red-500/10 text-red-500 border-red-500/20"
    }[status] || "bg-muted text-muted-foreground"
  end

  def can_cancel?
    %w[pending in_review on_hold approved].include?(status)
  end

  def can_unapprove?
    status == "approved"
  end

  def has_tracking?
    tracking_number.present? || tracking_url.present?
  end

  before_validation :calculate_total_shards, on: :create

  def approve!
    update!(status: "approved")
  end

  def fulfill!(fulfiller)
    transaction do
      update!(
        status: "fulfilled",
        fulfilled_at: Time.current,
        fulfilled_by: fulfiller
      )
      shop_item.decrement_stock!(quantity)
    end
  end

  def cancel!
    raise StandardError, "Order cannot be cancelled from #{status.humanize.downcase} status." unless can_cancel?

    transaction do
      user.credit_shards!(
        total_shards,
        transaction_type: "refund",
        transactable: self,
        description: "Order cancelled - refund for #{shop_item.name}"
      )
      update!(status: "cancelled")
    end
  end

  def mark_in_review!
    update!(status: "in_review")
  end

  def mark_on_hold!(notes = nil)
    update!(status: "on_hold", status_notes: notes)
  end

  def unapprove!
    raise StandardError, "Only approved orders can be unapproved." unless can_unapprove?

    update!(status: "in_review")
  end

  def add_tracking!(tracking_number: nil, tracking_url: nil)
    update!(tracking_number: tracking_number, tracking_url: tracking_url)
  end

  private

  def calculate_total_shards
    return if total_shards.present?
    return unless shop_item && quantity

    self.total_shards = shop_item.current_price * quantity
  end
end
