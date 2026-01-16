# frozen_string_literal: true

# Patch for phlex-rails compatibility with Rails 8.1+
# See: https://github.com/phlex-ruby/phlex-rails/issues/323
#
# Rails 8.1's ActionController::Live calls class_attribute in its included block,
# which fails when included in a plain module. This patch intercepts the require
# of phlex/rails/streaming and injects ActiveSupport::Concern before the module
# is defined.

require "active_support/concern"

# Pre-define the module structure with ActiveSupport::Concern
# before phlex-rails tries to define it
module Phlex
  module Rails
    module Streaming
      extend ActiveSupport::Concern

      included do
        include ActionController::Live
      end
    end
  end
end

# Mark the original file as already loaded to prevent zeitwerk from loading it
streaming_path = $LOAD_PATH
  .lazy
  .map { |p| File.join(p, "phlex/rails/streaming.rb") }
  .find { |f| File.exist?(f) }

if streaming_path
  $LOADED_FEATURES << streaming_path unless $LOADED_FEATURES.include?(streaming_path)
end
