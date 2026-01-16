# frozen_string_literal: true

require "openssl"
require "base64"
require "uri"
require "cgi"

# Custom ActiveStorage service for Azure Blob Storage using REST API
# Follows https://learn.microsoft.com/rest/api/storageservices/
class ActiveStorage::Service::AzureStorageService < ActiveStorage::Service
  attr_reader :account_name, :container, :sas_token, :access_key

  def initialize(account_name:, container:, sas_token: nil, access_key: nil, **options)
    @account_name = account_name
    @container = container
    @sas_token = sas_token
    @access_key = access_key
    @options = options
  end

  def upload(key, io, checksum: nil, content_type: nil, disposition: nil, filename: nil, **)
    instrument :upload, key: key, checksum: checksum do
      # Read content (rewind if needed to ensure we read from the start)
      io.rewind if io.respond_to?(:rewind)
      content = io.read

      url = blob_url_without_sas(key)
      headers = {
        "x-ms-blob-type" => "BlockBlob",
        "x-ms-version" => "2023-11-03",
        "Content-Type" => content_type || "application/octet-stream",
        "Content-Length" => content.bytesize.to_s
      }
      headers["Content-MD5"] = checksum if checksum
      if disposition && filename
        headers["x-ms-blob-content-disposition"] = "#{disposition}; filename=\"#{filename}\""
      end

      # Add authorization header if using access key
      if access_key.present?
        headers["Authorization"] = generate_auth_header("PUT", url, headers, content.bytesize)
        headers["x-ms-date"] = Time.now.utc.strftime("%a, %d %b %Y %H:%M:%S GMT")
      elsif sas_token.present?
        url = blob_url(key)
      end

      response = Faraday.put(url, content, headers)
      raise "Upload failed: #{response.status} - #{response.body}" unless response.success?
    end
  end

  def download(key, &block)
    if block_given?
      instrument :streaming_download, key: key do
        stream(key, &block)
      end
    else
      instrument :download, key: key do
        response = Faraday.get(blob_url(key))
        raise "Download failed: #{response.status}" unless response.success?
        response.body
      end
    end
  end

  def download_chunk(key, range)
    instrument :download_chunk, key: key, range: range do
      response = Faraday.get(blob_url(key)) do |req|
        req.headers["Range"] = "bytes=#{range.begin}-#{range.exclude_end? ? range.end - 1 : range.end}"
      end
      raise "Download chunk failed: #{response.status}" unless response.success?
      response.body
    end
  end

  def delete(key)
    instrument :delete, key: key do
      url = blob_url_without_sas(key)
      headers = {
        "x-ms-version" => "2023-11-03"
      }

      # Add authorization header if using access key
      if access_key.present?
        headers["x-ms-date"] = Time.now.utc.strftime("%a, %d %b %Y %H:%M:%S GMT")
        headers["Authorization"] = generate_auth_header("DELETE", url, headers, 0)
      elsif sas_token.present?
        url = blob_url(key)
      end

      response = Faraday.delete(url, nil, headers)
      # Azure returns 202 for successful delete
      raise "Delete failed: #{response.status}" unless [ 200, 202, 404 ].include?(response.status)
    end
  end

  def delete_prefixed(prefix)
    instrument :delete_prefixed, prefix: prefix do
      # List blobs with prefix and delete them
      blobs = list_blobs(prefix)
      blobs.each { |blob_key| delete(blob_key) }
    end
  end

  def exist?(key)
    instrument :exist, key: key do |payload|
      response = Faraday.head(blob_url(key))
      exists = response.success?
      payload[:exist] = exists
      exists
    end
  end

  def url_for_direct_upload(key, expires_in:, content_type:, content_length:, checksum:, custom_metadata: {})
    instrument :url, key: key do |payload|
      url = blob_url(key)
      payload[:url] = url
      url
    end
  end

  def headers_for_direct_upload(key, content_type:, checksum:, filename: nil, disposition: nil, custom_metadata: {}, **)
    headers = {
      "x-ms-blob-type" => "BlockBlob",
      "Content-Type" => content_type
    }
    headers["Content-MD5"] = checksum if checksum
    if disposition && filename
      headers["x-ms-blob-content-disposition"] = "#{disposition}; filename=\"#{filename}\""
    end
    custom_metadata.each { |k, v| headers["x-ms-meta-#{k}"] = v }
    headers
  end

  def private_url(key, expires_in:, filename:, disposition:, content_type:, **)
    # Azure Blob Storage with SAS token already provides authenticated access
    # The SAS token acts as the signature for private URLs
    blob_url(key)
  end

  def public_url(key, **)
    # For public access, return URL without SAS token
    escaped_key = key.to_s.split("/").map { |part| CGI.escape(part) }.join("/")
    "https://#{account_name}.blob.core.windows.net/#{container}/#{escaped_key}"
  end

  private

  def blob_url(key)
    escaped_key = key.to_s.split("/").map { |part| CGI.escape(part) }.join("/")
    url = "https://#{account_name}.blob.core.windows.net/#{container}/#{escaped_key}"
    url += "?#{sas_token}" if sas_token.present?
    url
  end

  def blob_url_without_sas(key)
    escaped_key = key.to_s.split("/").map { |part| CGI.escape(part) }.join("/")
    "https://#{account_name}.blob.core.windows.net/#{container}/#{escaped_key}"
  end

  def generate_auth_header(method, url, headers, content_length)
    return nil unless access_key.present?

    # Parse the URI to get the canonical resource
    uri = URI.parse(url)
    canonical_resource = "/#{account_name}#{uri.path}"

    # Build the string to sign
    # Format: VERB + "\n" + Content-Encoding + "\n" + Content-Language + "\n" + Content-Length + "\n" +
    #         Content-MD5 + "\n" + Content-Type + "\n" + Date + "\n" + If-Modified-Since + "\n" +
    #         If-Match + "\n" + If-None-Match + "\n" + If-Unmodified-Since + "\n" + Range + "\n" +
    #         CanonicalizedHeaders + CanonicalizedResource

    string_to_sign = [
      method,
      "", # Content-Encoding
      "", # Content-Language
      content_length > 0 ? content_length.to_s : "", # Content-Length
      headers["Content-MD5"] || "", # Content-MD5
      headers["Content-Type"] || "",
      "", # Date (we use x-ms-date instead)
      "", # If-Modified-Since
      "", # If-Match
      "", # If-None-Match
      "", # If-Unmodified-Since
      "", # Range
      canonicalized_headers(headers),
      canonical_resource
    ].join("\n")

    # Sign the string using HMAC-SHA256
    signature = Base64.strict_encode64(
      OpenSSL::HMAC.digest("SHA256", Base64.strict_decode64(access_key), string_to_sign)
    )

    "SharedKey #{account_name}:#{signature}"
  end

  def canonicalized_headers(headers)
    # Get all x-ms- headers, sort them, and format as "header:value\n"
    headers
      .select { |k, _| k.to_s.downcase.start_with?("x-ms-") }
      .sort_by { |k, _| k.to_s.downcase }
      .map { |k, v| "#{k.to_s.downcase}:#{v}" }
      .join("\n")
  end

  def list_blobs(prefix)
    url = "https://#{account_name}.blob.core.windows.net/#{container}"
    url += "?#{sas_token}&" if sas_token.present?
    url += "restype=container&comp=list&prefix=#{CGI.escape(prefix)}"

    response = Faraday.get(url)
    raise "List blobs failed: #{response.status}" unless response.success?

    # Parse XML response to extract blob names
    # Simple regex parsing - in production you might want to use Nokogiri
    response.body.scan(/<Name>([^<]+)<\/Name>/).flatten
  end

  def stream(key)
    response = Faraday.get(blob_url(key)) do |req|
      req.options.on_data = proc do |chunk, _|
        yield chunk
      end
    end
    raise "Stream failed: #{response.status}" unless response.success?
  end
end
