# frozen_string_literal: true

class ApiKey < ApplicationRecord
  belongs_to :campaign, inverse_of: :api_keys

  validates :name, presence: true
  validates :key_digest, presence: true, uniqueness: true
  validates :key_prefix, presence: true

  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :recent, -> { order(created_at: :desc) }
  scope :recently_used, -> { where.not(last_used_at: nil).order(last_used_at: :desc) }
  scope :with_campaign, -> { includes(:campaign) }

  attr_accessor :raw_key

  before_validation :generate_key, on: :create

  def self.authenticate(key)
    return nil if key.blank?

    prefix = key[0..7]
    api_key = active.find_by(key_prefix: prefix)
    return nil unless api_key

    return nil unless api_key.key_matches?(key)

    api_key.touch(:last_used_at)
    api_key.increment!(:request_count)
    api_key
  end

  def key_matches?(key)
    BCrypt::Password.new(key_digest) == key
  rescue BCrypt::Errors::InvalidHash
    false
  end

  def deactivate!
    update!(active: false)
  end

  def has_permission?(resource, action)
    return true if permissions.blank? # No restrictions means full access

    resource_permissions = permissions[resource.to_s]
    return false if resource_permissions.nil?

    resource_permissions.include?(action.to_s)
  end

  private

  def generate_key
    self.raw_key = "pyr_#{SecureRandom.hex(24)}"
    self.key_prefix = raw_key[0..7]
    self.key_digest = BCrypt::Password.create(raw_key)
  end
end
