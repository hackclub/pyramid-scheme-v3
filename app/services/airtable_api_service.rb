# frozen_string_literal: true

# Service for interacting with Airtable Meta API
# Used for discovering bases and tables for campaign configuration
class AirtableApiService
  PERSONAL_ACCESS_TOKEN = ENV.fetch("AIRTABLE_PAT", nil)
  META_API_BASE = "https://api.airtable.com/v0/meta"

  class ApiError < StandardError; end

  # Fetch all accessible bases
  def list_bases
    response = make_request("#{META_API_BASE}/bases")
    data = JSON.parse(response.body)

    data["bases"]&.map do |base|
      {
        id: base["id"],
        name: base["name"],
        permission_level: base["permissionLevel"]
      }
    end || []
  rescue StandardError => e
    Rails.logger.error "[AirtableApi] Failed to list bases: #{e.message}"
    raise ApiError, "Failed to fetch Airtable bases: #{e.message}"
  end

  # Fetch schema for a specific base (tables and fields)
  def get_base_schema(base_id)
    response = make_request("#{META_API_BASE}/bases/#{base_id}/tables")
    data = JSON.parse(response.body)

    data["tables"]&.map do |table|
      {
        id: table["id"],
        name: table["name"],
        primary_field_id: table["primaryFieldId"],
        fields: table["fields"]&.map do |field|
          {
            id: field["id"],
            name: field["name"],
            type: field["type"],
            description: field["description"]
          }
        end || []
      }
    end || []
  rescue StandardError => e
    Rails.logger.error "[AirtableApi] Failed to get base schema for #{base_id}: #{e.message}"
    raise ApiError, "Failed to fetch Airtable base schema: #{e.message}"
  end

  # Fetch records from a specific table
  def fetch_table_records(base_id, table_id, max_records: 100)
    url = "https://api.airtable.com/v0/#{base_id}/#{table_id}?maxRecords=#{max_records}"
    response = make_request(url)
    data = JSON.parse(response.body)

    data["records"] || []
  rescue StandardError => e
    Rails.logger.error "[AirtableApi] Failed to fetch records: #{e.message}"
    raise ApiError, "Failed to fetch Airtable records: #{e.message}"
  end

  private

  def make_request(url)
    raise ApiError, "Airtable PAT not configured" unless PERSONAL_ACCESS_TOKEN.present?

    response = Faraday.get(url) do |req|
      req.headers["Authorization"] = "Bearer #{PERSONAL_ACCESS_TOKEN}"
      req.headers["Content-Type"] = "application/json"
    end

    unless response.success?
      error_body = begin
        JSON.parse(response.body)
      rescue JSON::ParserError
        { "error" => response.body }
      end
      raise ApiError, "Airtable API error (#{response.status}): #{error_body.dig('error', 'message') || error_body}"
    end

    response
  end
end
