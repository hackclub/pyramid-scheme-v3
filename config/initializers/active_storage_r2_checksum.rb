# frozen_string_literal: true

require "active_storage/service/s3_service"

module ActiveStorageR2ChecksumPatch
  def upload(key, io, checksum: nil, **options)
    checksum = nil if r2_endpoint?
    super
  end

  def headers_for_direct_upload(key, content_type:, checksum:, filename: nil, disposition: nil, custom_metadata: {}, **options)
    checksum = nil if r2_endpoint?
    super
  end

  private

  def r2_endpoint?
    endpoint = client&.config&.endpoint&.to_s
    endpoint.present? && endpoint.include?("r2")
  rescue StandardError
    false
  end
end

ActiveStorage::Service::S3Service.prepend(ActiveStorageR2ChecksumPatch)

# Cloudflare R2 rejects requests when multiple checksum headers are provided.
# Keep SDK checksum behavior minimal for S3-compatible endpoints like R2.
if defined?(Aws)
  Aws.config[:s3] ||= {}
  Aws.config[:s3].merge!(
    request_checksum_calculation: "when_required",
    response_checksum_validation: "when_required"
  )
end
