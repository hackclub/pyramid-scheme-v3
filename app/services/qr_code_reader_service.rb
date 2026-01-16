# frozen_string_literal: true

require "faraday"
require "faraday/multipart"

# Reads QR codes from images using the QReader microservice.
#
# This service acts as a client to an external QR code reading service,
# supporting multiple input formats (binary data, file paths, uploads).
#
# @example Read QR codes from an image file
#   reader = QrCodeReaderService.new
#   codes = reader.read_from_file("/path/to/image.png")
#   # => ["https://example.com/ref/ABC123"]
#
# @example Parse a poster QR code URL
#   reader = QrCodeReaderService.new
#   data = reader.parse_poster_qr("https://example.com/scan?p=123&u=456")
#   # => { poster_id: "123", user_id: "456", location: nil }
class QrCodeReaderService
  class QrReaderError < StandardError; end

  # Default timeout for QR reader requests (seconds)
  REQUEST_TIMEOUT = 60
  OPEN_TIMEOUT = 10

  def initialize
    # Coolify uses UUID-based internal hostnames, fallback to localhost for development
    @qreader_url = ENV.fetch("QREADER_URL", nil)
    @qreader_url ||= Rails.env.production? ? "http://akk40c4008cww40kk0kg0k4s:4445" : "http://localhost:4445"
    @admin_key = ENV.fetch("ADMIN_KEY", "")
  end

  # Read QR codes from an image using the QReader microservice
  # @param image_data [String] Binary image data
  # @return [Array<String>] Array of decoded QR code values
  def read_from_image(image_data)
    response = connection.post("/read") do |req|
      req.headers["x-admin-key"] = @admin_key
      req.headers["Content-Type"] = "multipart/form-data"
      req.body = { file: Faraday::Multipart::FilePart.new(StringIO.new(image_data), "image/png") }
      req.options.timeout = REQUEST_TIMEOUT
      req.options.open_timeout = OPEN_TIMEOUT
    end

    unless response.success?
      error_msg = begin
        parsed = JSON.parse(response.body)
        # Handle both our custom "error" key and FastAPI's default "detail" key
        parsed["error"] || parsed["detail"] || response.body.to_s.truncate(200)
      rescue JSON::ParserError
        response.body.to_s.truncate(200)
      end
      raise QrReaderError, "QReader service error (#{response.status}): #{error_msg}"
    end

    begin
      result = JSON.parse(response.body)
      result["results"] || []
    rescue JSON::ParserError => e
      raise QrReaderError, "Invalid response from QReader: #{e.message}"
    end
  end

  # Read QR codes from a file path
  # @param file_path [String] Path to the image file
  # @return [Array<String>] Array of decoded QR code values
  def read_from_file(file_path)
    raise QrReaderError, "File not found: #{file_path}" unless File.exist?(file_path)

    image_data = File.binread(file_path)
    read_from_image(image_data)
  end

  # Read QR codes from an uploaded file (ActionDispatch::Http::UploadedFile)
  # @param uploaded_file [ActionDispatch::Http::UploadedFile] The uploaded file
  # @return [Array<String>] Array of decoded QR code values
  def read_from_upload(uploaded_file)
    image_data = uploaded_file.read
    read_from_image(image_data)
  end

  # Parse a scanned QR code URL and extract poster data
  # @param qr_content [String] The decoded QR code content
  # @return [Hash, nil] Hash with poster_id, user_id, location or nil if invalid
  def parse_poster_qr(qr_content)
    return nil unless qr_content.present?

    uri = URI.parse(qr_content)
    params = Rack::Utils.parse_query(uri.query)

    return nil unless params["p"] && params["u"]

    {
      poster_id: params["p"],
      user_id: params["u"],
      location: params["l"]
    }
  rescue URI::InvalidURIError
    nil
  end

  private

  def connection
    @connection ||= Faraday.new(url: @qreader_url) do |f|
      f.request :multipart
      f.adapter Faraday.default_adapter
    end
  end
end
