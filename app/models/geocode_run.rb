# frozen_string_literal: true

class GeocodeRun < ApplicationRecord
  enum :status, {
    running: "running",
    succeeded: "succeeded",
    failed: "failed"
  }

  validates :status, presence: true

  scope :recent, -> { order(started_at: :desc) }

  def self.latest
    recent.first
  end

  def duration_display
    return nil unless duration_seconds
    if duration_seconds < 1
      "#{(duration_seconds * 1000).round}ms"
    elsif duration_seconds < 60
      "#{duration_seconds.round(1)}s"
    else
      "#{(duration_seconds / 60).round(1)}m"
    end
  end
end
