# frozen_string_literal: true

class Campaign < ApplicationRecord
  has_many :referrals, dependent: :destroy, inverse_of: :campaign
  has_many :posters, dependent: :destroy, inverse_of: :campaign
  has_many :api_keys, dependent: :destroy, inverse_of: :campaign
  has_many :user_emblems, dependent: :destroy, inverse_of: :campaign
  has_many :campaign_assets, dependent: :destroy, inverse_of: :campaign
  has_many :airtable_referrals, dependent: :destroy, inverse_of: :campaign
  has_many :airtable_sync_runs, dependent: :destroy
  has_many :video_submissions, dependent: :destroy, inverse_of: :campaign
  has_many :participants, through: :user_emblems, source: :user

  # Campaign statuses
  STATUSES = %w[open closed coming_soon].freeze

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9-]+\z/, message: "only allows lowercase letters, numbers, and hyphens" }
  validates :theme, presence: true
  validates :referral_shards, numericality: { greater_than_or_equal_to: 0 }
  validates :poster_shards, numericality: { greater_than_or_equal_to: 0 }
  validates :required_coding_minutes, numericality: { greater_than: 0 }
  validates :subdomain, uniqueness: true, allow_nil: true, format: { with: /\A[a-z0-9-]+\z/, message: "only allows lowercase letters, numbers, and hyphens" }
  validates :status, inclusion: { in: STATUSES }

  # Default Airtable field mappings
  DEFAULT_FIELD_MAPPINGS = {
    "email" => "Email",
    "hours" => "Hours",
    "idv_status" => "IDV Status",
    "referral_code" => "ref",
    "projects_shipped" => "Projects Shipped"
  }.freeze

  scope :active, -> { where(active: true) }
  scope :current, -> { active.where("starts_at IS NULL OR starts_at <= ?", Time.current).where("ends_at IS NULL OR ends_at >= ?", Time.current) }
  scope :with_airtable_sync, -> { where(airtable_sync_enabled: true) }
  scope :by_subdomain, ->(subdomain) { where(subdomain: subdomain) }
  scope :open_status, -> { where(status: "open") }
  scope :coming_soon, -> { where(status: "coming_soon") }
  scope :not_closed, -> { where.not(status: "closed") }
  scope :visible_to_public, -> { active.not_closed }

  def self.flavortown
    find_by(slug: "flavortown")
  end

  def self.find_by_subdomain(subdomain)
    return nil if subdomain.blank?
    by_subdomain(subdomain).first
  end

  # Status helpers
  def open?
    status == "open"
  end

  def closed?
    status == "closed"
  end

  def coming_soon?
    status == "coming_soon"
  end

  # Check if user can access this campaign
  def accessible_by?(user)
    return true if open?
    return false if closed?
    return user&.admin? if coming_soon?
    false
  end

  def running?
    active? && open? && (starts_at.nil? || starts_at <= Time.current) && (ends_at.nil? || ends_at >= Time.current)
  end

  def theme_class
    "theme-#{theme}"
  end

  # Get the referral base URL for this campaign
  def referral_base_url
    return base_url if base_url.present?
    return "https://#{subdomain}.hack.club" if subdomain.present?
    "https://#{slug}.hack.club"
  end

  # Get full referral URL with code
  def referral_url_for(code)
    "#{referral_base_url}/?ref=#{code}"
  end

  # Airtable configuration helpers
  def airtable_configured?
    airtable_base_id.present? && airtable_table_id.present? && airtable_sync_enabled?
  end

  # Check if campaign uses global Airtable fallback (no campaign-specific base configured)
  def uses_global_airtable?
    airtable_base_id.blank? && ENV["AIRTABLE_BASE_ID"].present?
  end

  # Check if Airtable sync is working (either via campaign config or global fallback)
  def airtable_sync_working?
    airtable_configured? || uses_global_airtable?
  end

  def airtable_field_mapping_for(field)
    mappings = airtable_field_mappings.presence || DEFAULT_FIELD_MAPPINGS
    mappings[field.to_s]
  end

  def effective_field_mappings
    DEFAULT_FIELD_MAPPINGS.merge(airtable_field_mappings || {})
  end

  # Poster template helpers
  def poster_template_for(variant)
    campaign_assets.poster_templates.active.by_variant(variant).first
  end

  def poster_preview_for(variant)
    campaign_assets.poster_previews.active.by_variant(variant).first
  end

  def poster_qr_config_for(variant)
    (poster_qr_coordinates || {})[variant] || default_qr_config_for(variant)
  end

  def default_qr_config_for(variant)
    case variant
    when "color"
      { "x" => 847, "y" => 119, "size" => 218 }
    when "bw"
      { "x" => 530, "y" => 122, "size" => 218 }
    when "printer_efficient"
      { "x" => 847, "y" => 119, "size" => 218 }
    else
      { "x" => 847, "y" => 119, "size" => 218 }
    end
  end

  # Custom CSS for theming
  def custom_stylesheet_url
    css_asset = campaign_assets.where(asset_type: "css").active.first
    css_asset&.file_url
  end

  # I18n override helpers
  def i18n_for(key, default: nil)
    return default unless i18n_overrides.present?
    i18n_overrides.dig(*key.to_s.split(".")) || default
  end

  def leaderboard_referrals
    User.joins(:referrals_given)
        .where(referrals: { campaign_id: id, status: :completed })
        .on_leaderboard
        .group("users.id")
        .select("users.*, COUNT(referrals.id) as campaign_referral_count")
      .order(Arel.sql("COUNT(referrals.id) DESC"))
  end

  def leaderboard_posters
    User.joins(:posters)
        .where(posters: { campaign_id: id, verification_status: "success" })
        .on_leaderboard
        .group("users.id")
        .select("users.*, COUNT(posters.id) as campaign_poster_count")
        .order(Arel.sql("COUNT(posters.id) DESC"))
  end
end
