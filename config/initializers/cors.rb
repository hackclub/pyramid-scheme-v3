# frozen_string_literal: true

# Configure CORS for frontend domains
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # Build allowed origins list
    allowed_origins = [
      "https://flavortown.hack.club",
      "https://sleepover.hack.club",
      "https://pyramid.hackclub.com"
    ]

    # Allow localhost for development only
    unless Rails.env.production?
      allowed_origins += [
        "http://localhost:3000",
        "http://localhost:4444"
      ]
    end

    # Add APP_HOST from environment if set and not already in list
    app_host = Rails.application.config.x.app_host
    allowed_origins << app_host if app_host.present? && !allowed_origins.include?(app_host)

    origins(*allowed_origins)

    resource "*",
      headers: :any,
      methods: [ :get, :post, :put, :patch, :delete, :options, :head ],
      credentials: true,
      max_age: 600
  end
end
