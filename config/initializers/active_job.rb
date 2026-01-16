# frozen_string_literal: true

# Configure ActiveJob to use async adapter (in-memory)
# Jobs process in the same Ruby process, no external dependencies needed
Rails.application.config.active_job.queue_adapter = :async
