# frozen_string_literal: true

require "net/http"
require "json"

class AirtableClient
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class ApiError < Error; end

  def initialize(api_key: nil, base_id: nil)
    @api_key = api_key || ENV["AIRTABLE_PAT"] || ENV["AIRTABLE_API_KEY"]
    @base_id = base_id || ENV["AIRTABLE_BASE_ID"]

    validate_configuration!
  end

  # Fetch all records from a table
  # @param table_name [String] The name of the Airtable table
  # @param formula [String] Optional Airtable formula for filtering
  # @return [Array<Hash>] Array of records with their fields and metadata
  def fetch_all(table_name, formula: nil)
    all_records = []
    offset = nil

    loop do
      url = "https://api.airtable.com/v0/#{@base_id}/#{CGI.escape(table_name)}"
      uri = URI(url)

      params = {}
      params[:filterByFormula] = formula if formula.present?
      params[:offset] = offset if offset.present?
      uri.query = URI.encode_www_form(params) if params.any?

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"] = "application/json"

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise ApiError, "Airtable API error: #{response.code} - #{response.body}"
      end

      data = JSON.parse(response.body)
      records = data["records"] || []

      records.each do |record|
        all_records << {
          id: record["id"],
          fields: record["fields"],
          created_time: record["createdTime"]
        }
      end

      offset = data["offset"]
      break unless offset.present?
    end

    all_records
  rescue JSON::ParserError => e
    raise ApiError, "Failed to parse Airtable response: #{e.message}"
  rescue StandardError => e
    raise ApiError, "Failed to fetch records from #{table_name}: #{e.message}"
  end

  # Fetch records that have been modified since a given time
  # @param table_name [String] The name of the Airtable table
  # @param since [Time] Only fetch records modified after this time
  # @return [Array<Hash>] Array of records
  def fetch_modified_since(table_name, since)
    # Airtable's LAST_MODIFIED_TIME() function returns records modified after the given time
    formula = "IS_AFTER(LAST_MODIFIED_TIME(), '#{since.iso8601}')"
    fetch_all(table_name, formula: formula)
  end

  # Fetch a single record by ID
  # @param table_name [String] The name of the Airtable table
  # @param record_id [String] The Airtable record ID
  # @return [Hash] The record data
  def fetch_record(table_name, record_id)
    url = "https://api.airtable.com/v0/#{@base_id}/#{CGI.escape(table_name)}/#{record_id}"
    uri = URI(url)

    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{@api_key}"
    request["Content-Type"] = "application/json"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    unless response.is_a?(Net::HTTPSuccess)
      raise ApiError, "Airtable API error: #{response.code} - #{response.body}"
    end

    record = JSON.parse(response.body)

    {
      id: record["id"],
      fields: record["fields"],
      created_time: record["createdTime"]
    }
  rescue JSON::ParserError => e
    raise ApiError, "Failed to parse Airtable response: #{e.message}"
  rescue StandardError => e
    raise ApiError, "Failed to fetch record #{record_id} from #{table_name}: #{e.message}"
  end

  private

  def validate_configuration!
    if @api_key.blank?
      raise ConfigurationError, "AIRTABLE_PAT or AIRTABLE_API_KEY is not set. Airtable integration is optional - set this only if you want to import data from Airtable."
    end

    if @base_id.blank?
      raise ConfigurationError, "AIRTABLE_BASE_ID is not set. Airtable integration is optional - set this only if you want to import data from Airtable."
    end
  end
end
