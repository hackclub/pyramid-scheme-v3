# frozen_string_literal: true

# Helper module for accessing app configuration
module Pyramid
  def self.base_url
    Rails.application.config.x.app_host
  end

  def self.localhost_url?(url)
    host = URI.parse(url).host
    host.present? && host.match?(/\A(localhost|127\.0\.0\.1|0\.0\.0\.0)\z/i)
  rescue URI::InvalidURIError
    false
  end
end

# Pyramid application configuration
Rails.application.configure do
  # Application host for generating URLs
  # In production, this should be set via APP_HOST environment variable
  # Example: https://pyramid.hackclub.com (or your custom domain)
  config.x.app_host ||= begin
    default_host = Rails.env.production? ? "https://pyramid.hackclub.com" : "http://localhost:4444"
    env_host = ENV["APP_HOST"].presence

    if Rails.env.production? && env_host.present? && Pyramid.localhost_url?(env_host)
      Rails.logger.warn "APP_HOST points to localhost in production; falling back to #{default_host}"
      env_host = nil
    end

    env_host.presence || default_host
  end

  # QReader microservice URL
  config.x.qreader_url = ENV.fetch("QREADER_URL", "http://localhost:4445")
end
