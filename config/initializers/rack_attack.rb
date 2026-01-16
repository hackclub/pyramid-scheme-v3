# frozen_string_literal: true

# Relaxed rate limiting to prevent abuse while allowing normal usage
class Rack::Attack
  # Use memory store for rate limiting (avoids SolidCache table dependency)
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  ### Throttle Rules ###

  # Limit authentication attempts - relaxed: 10 per minute per IP
  throttle("auth/ip", limit: 10, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/auth", "/oauth")
  end

  # Limit API requests - relaxed: 120 per minute per API key
  throttle("api/key", limit: 120, period: 1.minute) do |req|
    if req.path.start_with?("/api/")
      req.env["HTTP_AUTHORIZATION"]&.gsub(/^Bearer\s+/, "")&.first(8)
    end
  end

  # Limit worker API - 30 per minute (internal service)
  throttle("worker/ip", limit: 30, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/api/v1/worker")
  end

  # Limit video submissions - 2 per hour per user (handled in controller, but add IP limit as fallback)
  throttle("video_submissions/ip", limit: 10, period: 1.hour) do |req|
    req.ip if req.path.match?(%r{^/c/[^/]+/videos$}) && req.post?
  end

  # General request throttle - relaxed: 300 per minute per IP
  throttle("req/ip", limit: 300, period: 1.minute, &:ip)

  ### Safelist Rules ###

  # Allow health checks without limits
  safelist("allow-health-checks") do |req|
    req.path == "/up" || req.path == "/healthy"
  end

  # Allow localhost in development
  safelist("allow-localhost") do |req|
    req.ip == "127.0.0.1" || req.ip == "::1" if Rails.env.development?
  end

  # Allow admin users (exempt from rate limiting)
  safelist("allow-admins") do |req|
    user_id = req.env.dig("rack.session", "user_id")
    user_id && User.find_by(id: user_id)&.admin?
  end

  ### Response Configuration ###

  # Return 429 Too Many Requests
  self.throttled_responder = lambda do |req|
    retry_after = (req.env["rack.attack.match_data"] || {})[:period]

    # Check if request accepts Turbo Streams
    if req.env["HTTP_ACCEPT"]&.include?("turbo-stream")
      # Just return empty response - let client-side handle it
      [
        429,
        {
          "Content-Type" => "text/plain",
          "Retry-After" => retry_after.to_s
        },
        [ "" ]
      ]
    elsif req.env["HTTP_ACCEPT"]&.include?("text/html")
      [
        429,
        {
          "Content-Type" => "text/html",
          "Retry-After" => retry_after.to_s
        },
        [ "<div class='alert alert-error'>Rate limit exceeded. Please wait #{retry_after} seconds before trying again.</div>" ]
      ]
    else
      [
        429,
        {
          "Content-Type" => "application/json",
          "Retry-After" => retry_after.to_s
        },
        [ { error: "Rate limit exceeded. Retry after #{retry_after} seconds." }.to_json ]
      ]
    end
  end
end
