# frozen_string_literal: true

class AirtableSyncRun < ApplicationRecord
  enum :status, {
    running: "running",
    succeeded: "succeeded",
    failed: "failed"
  }

  validates :status, presence: true
end
