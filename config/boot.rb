ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.

# Patch phlex-rails Streaming module for Rails 8.1+ compatibility
# This must be loaded before Rails/zeitwerk to prevent the original file from loading
# See: https://github.com/phlex-ruby/phlex-rails/issues/323
require_relative "../lib/boot_patches/phlex_rails_streaming"
