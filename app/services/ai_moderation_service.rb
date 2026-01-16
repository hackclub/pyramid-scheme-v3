# frozen_string_literal: true

require "net/http"
require "json"

# Service to check content against Hack Club AI moderation API
class AiModerationService
  API_URL = "https://ai.hackclub.com/proxy/v1/moderations"

  class ModerationResult
    attr_reader :flagged, :categories, :error

    def initialize(flagged:, categories: {}, error: nil)
      @flagged = flagged
      @categories = categories
      @error = error
    end

    def safe?
      !flagged && error.nil?
    end

    def flagged?
      flagged == true
    end

    def error?
      error.present?
    end

    def flagged_categories
      categories.select { |_, v| v == true }.keys
    end
  end

  class << self
    def moderate(text)
      return ModerationResult.new(flagged: false) if text.blank?

      uri = URI(API_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"

      # Add authorization if API key is configured
      if api_key.present?
        request["Authorization"] = "Bearer #{api_key}"
      end

      request.body = { input: text }.to_json

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.error("AI Moderation API error: #{response.code} - #{response.body}")
        return ModerationResult.new(flagged: false, error: "API request failed: #{response.code}")
      end

      parse_response(response.body)
    rescue StandardError => e
      Rails.logger.error("AI Moderation API exception: #{e.message}")
      ModerationResult.new(flagged: false, error: e.message)
    end

    def safe?(text)
      moderate(text).safe?
    end

    def flagged?(text)
      moderate(text).flagged?
    end

    private

    def api_key
      ENV["HACKCLUB_AI_API_KEY"]
    end

    def parse_response(body)
      data = JSON.parse(body)
      results = data.dig("results", 0)

      return ModerationResult.new(flagged: false, error: "No results in response") if results.nil?

      ModerationResult.new(
        flagged: results["flagged"] == true,
        categories: results["categories"] || {}
      )
    rescue JSON::ParserError => e
      ModerationResult.new(flagged: false, error: "Failed to parse response: #{e.message}")
    end
  end
end
