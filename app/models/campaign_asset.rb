# frozen_string_literal: true

class CampaignAsset < ApplicationRecord
  belongs_to :campaign, inverse_of: :campaign_assets

  has_one_attached :file

  ASSET_TYPES = %w[
    poster_template
    poster_preview
    logo
    background
    css
    favicon
    og_image
  ].freeze

  POSTER_VARIANTS = %w[color bw printer_efficient].freeze

  validates :asset_type, presence: true, inclusion: { in: ASSET_TYPES }
  validates :name, presence: true
  validates :variant, inclusion: { in: POSTER_VARIANTS }, allow_nil: true
  validates :file, presence: true, on: :create

  validates :file,
    content_type: {
      in: %w[application/pdf image/png image/jpeg image/webp image/svg+xml text/css image/x-icon image/vnd.microsoft.icon],
      message: "must be a valid file format"
    },
    size: { less_than: 50.megabytes, message: "must be less than 50MB" },
    if: -> { file.attached? }

  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :poster_templates, -> { where(asset_type: "poster_template") }
  scope :poster_previews, -> { where(asset_type: "poster_preview") }
  scope :logos, -> { where(asset_type: "logo") }
  scope :by_variant, ->(variant) { where(variant: variant) }
  scope :by_type, ->(type) { where(asset_type: type) }
  scope :with_file, -> { includes(file_attachment: :blob) }

  def poster_template?
    asset_type == "poster_template"
  end

  def poster_preview?
    asset_type == "poster_preview"
  end

  def css?
    asset_type == "css"
  end

  def file_url
    return nil unless file.attached?
    Rails.application.routes.url_helpers.rails_blob_url(file, only_path: false)
  end
end
