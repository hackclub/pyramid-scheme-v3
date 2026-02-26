# frozen_string_literal: true

class RefSourceClick < ApplicationRecord
  validates :ref_source, presence: true

  scope :for_source, ->(source) { where(ref_source: source) }

  # Log a click from a request (non-blocking, best-effort)
  def self.log(ref_source, request)
    create!(
      ref_source: ref_source,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      path: request.fullpath
    )
  rescue StandardError => e
    Rails.logger.error("Failed to log ref source click: #{e.message}")
  end

  # Count clicks grouped by ref_source
  def self.click_counts
    group(:ref_source).count
  end

  # Count unique IPs grouped by ref_source
  def self.unique_click_counts
    group(:ref_source).distinct.count(:ip_address)
  end
end
