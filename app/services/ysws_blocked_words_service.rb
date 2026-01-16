# frozen_string_literal: true

require "net/http"
require "rexml/document"

# Fetches and checks against blocked words from the YSWS (You Ship, We Ship) feed.
#
# YSWS project titles are reserved and cannot be used as custom referral codes.
# The blocked words list is cached for 1 hour to avoid excessive API calls.
#
# @example Check if a code is blocked
#   YswsBlockedWordsService.blocked?("some-project") # => true/false
#
# @example Force refresh the cache
#   YswsBlockedWordsService.clear_cache!
class YswsBlockedWordsService
  # URL of the YSWS RSS/Atom feed
  FEED_URL = "https://ysws.hackclub.com/feed.xml"
  # Cache key for storing blocked titles
  CACHE_KEY = "ysws_blocked_titles"
  # Duration to cache the blocked titles list
  CACHE_DURATION = 1.hour

  class << self
    def blocked_titles
      Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_DURATION) do
        fetch_titles_from_feed
      end
    end

    # Checks if a code matches any blocked YSWS project title.
    #
    # @param code [String] The code to check
    # @return [Boolean] True if the code is blocked
    def blocked?(code)
      return false if code.blank?

      normalized_code = normalize(code)
      blocked_titles.any? { |title| normalize(title) == normalized_code }
    end

    # Clears the cached blocked titles, forcing a fresh fetch on next check.
    #
    # @return [void]
    def clear_cache!
      Rails.cache.delete(CACHE_KEY)
    end

    private

    def fetch_titles_from_feed
      uri = URI(FEED_URL)
      response = Net::HTTP.get_response(uri)

      return [] unless response.is_a?(Net::HTTPSuccess)

      parse_titles_from_xml(response.body)
    rescue StandardError => e
      Rails.logger.error("Failed to fetch YSWS feed: #{e.message}")
      []
    end

    def parse_titles_from_xml(xml_content)
      doc = REXML::Document.new(xml_content)
      titles = []

      # Parse RSS feed items
      doc.elements.each("//item/title") do |element|
        titles << element.text if element.text.present?
      end

      # Also try Atom feed entries as fallback
      doc.elements.each("//entry/title") do |element|
        titles << element.text if element.text.present?
      end

      titles.uniq
    end

    def normalize(text)
      # Remove spaces, downcase, and strip non-alphabetic characters
      text.to_s.downcase.gsub(/[^a-z]/, "")
    end
  end
end
