# frozen_string_literal: true

# Automatically verifies poster submissions by reading QR codes from proof images.
#
# This service attempts to verify that a poster's proof image contains a valid
# QR code matching the poster's referral URL. If the QR code matches a different
# poster owned by the same user, it will auto-match and transfer the proof.
#
# @example Verify a poster
#   service = PosterAutoVerificationService.new(poster)
#   result = service.call
#   case result
#   when :success then puts "Poster verified!"
#   when :auto_matched then puts "Matched to poster #{service.matched_poster.id}"
#   when :in_review then puts "Requires manual review"
#   end
class PosterAutoVerificationService
  class VerificationError < StandardError; end

  attr_reader :matched_poster

  # Initializes the verification service for a poster.
  #
  # @param poster [Poster] The poster to verify
  def initialize(poster)
    @poster = poster
    @matched_poster = nil
  end

  # @return [Symbol] :success, :auto_matched, or :in_review
  def call
    # Initialize metadata tracking
    @poster.metadata ||= {}
    @poster.metadata["auto_verification_attempted_at"] = Time.current.iso8601
    @poster.metadata["expected_url"] = @poster.referral_url

    unless @poster.proof_image.attached?
      @poster.metadata["auto_verification_error"] = "No proof image attached"
      @poster.save!
      return :in_review
    end

    temp_file = nil
    begin
      # Download the proof image to a temp file
      temp_file = Tempfile.new([ "proof", ".jpg" ])
      temp_file.binmode
      @poster.proof_image.download { |chunk| temp_file.write(chunk) }
      temp_file.rewind

      # Use the QrCodeReaderService which calls the qreader microservice
      qr_reader = QrCodeReaderService.new
      detected_qr_codes = qr_reader.read_from_file(temp_file.path)

      # Store detected QR codes in metadata
      @poster.metadata["detected_qr_codes"] = detected_qr_codes
      @poster.save!

      qr_match_found = detected_qr_codes.any? { |qr| qr_matches_poster?(qr, @poster) }

      if qr_match_found
        handle_success
        :success
      else
        # Try to auto-match to one of the user's OTHER pending posters
        auto_match_result = try_auto_match_to_user_posters(detected_qr_codes)
        if auto_match_result
          :auto_matched
        else
          handle_qr_not_found
          :in_review
        end
      end
    rescue QrCodeReaderService::QrReaderError => e
      handle_qr_reader_error(e)
      :in_review
    rescue => e
      handle_general_error(e)
      :in_review
    ensure
      cleanup_temp_file(temp_file)
    end
  end

  private

  # Try to match detected QR codes to any of the user's pending posters
  # If found, transfer the proof to that poster and auto-approve it
  def try_auto_match_to_user_posters(detected_qr_codes)
    return false unless @poster.user.present?
    return false if detected_qr_codes.empty?

    # Get all user's pending posters (excluding the current one)
    user_pending_posters = @poster.user.posters
      .where(verification_status: "pending")
      .where.not(id: @poster.id)
      .where(campaign_id: @poster.campaign_id)

    return false if user_pending_posters.empty?

    # Try to find a matching poster
    detected_qr_codes.each do |qr|
      user_pending_posters.each do |candidate_poster|
        if qr_matches_poster?(qr, candidate_poster)
          # Found a match! Transfer proof and auto-approve
          transfer_proof_and_approve(candidate_poster, qr)
          @matched_poster = candidate_poster
          return true
        end
      end
    end

    false
  end

  # Transfer the proof image from the original poster to the matched poster
  def transfer_proof_and_approve(matched_poster, matched_qr_code)
    # Copy the proof image to the matched poster
    matched_poster.proof_image.attach(@poster.proof_image.blob)

    # Copy location if not set on matched poster
    if matched_poster.location_description.blank? && @poster.location_description.present?
      matched_poster.location_description = @poster.location_description
    end

    # Update metadata on matched poster
    matched_poster.metadata ||= {}
    matched_poster.metadata["auto_matched_from_poster_id"] = @poster.id
    matched_poster.metadata["auto_matched_qr_code"] = matched_qr_code
    matched_poster.metadata["detected_qr_codes"] = @poster.metadata["detected_qr_codes"]
    matched_poster.metadata["auto_verification_attempted_at"] = Time.current.iso8601

    # Auto-approve the matched poster
    matched_poster.complete_auto_verification!

    # Update the original poster to note the transfer
    @poster.metadata["proof_transferred_to_poster_id"] = matched_poster.id
    @poster.metadata["auto_match_transfer_at"] = Time.current.iso8601
    @poster.save!

    # Send notification for the matched poster
    if matched_poster.user.present? && matched_poster.campaign.present?
      SlackNotificationService.new.notify_poster_verified(
        user: matched_poster.user,
        poster: matched_poster,
        shards: matched_poster.campaign.poster_shards
      )
    end
  end

  def handle_success
    @poster.complete_auto_verification!
    send_verification_notifications
  end

  def handle_qr_not_found
    mark_for_review(
      verification_result: "qr_not_found",
      expected_url: @poster.referral_url
    )
  end

  def handle_qr_reader_error(error)
    Rails.logger.error "QR Reader service error: #{error.message}"
    mark_for_review(
      error_message: "QR Reader: #{error.message}",
      expected_url: @poster.referral_url
    )
  end

  def handle_general_error(error)
    Rails.logger.error "Failed to auto-verify proof: #{error.class} - #{error.message}\n#{error.backtrace.first(5).join("\n")}"
    mark_for_review(error_message: "#{error.class}: #{error.message}")
  end

  # Marks the poster for manual review and sends admin notification.
  #
  # @param verification_result [String, nil] The verification result code
  # @param error_message [String, nil] The error message if verification failed
  # @param expected_url [String, nil] The expected QR code URL
  def mark_for_review(verification_result: nil, error_message: nil, expected_url: nil)
    @poster.metadata ||= {}
    @poster.metadata["auto_verification_result"] = verification_result if verification_result
    @poster.metadata["auto_verification_error"] = error_message if error_message
    @poster.metadata["auto_verification_attempted_at"] = Time.current.iso8601
    @poster.metadata["expected_url"] = expected_url if expected_url
    @poster.verification_status = "in_review"
    @poster.save!

    SlackNotificationService.new.notify_admin_new_poster(poster: @poster)
  end

  # Sends notifications for successful verification.
  def send_verification_notifications
    if @poster.user.present? && @poster.campaign.present?
      SlackNotificationService.new.notify_poster_verified(
        user: @poster.user,
        poster: @poster,
        shards: @poster.campaign.poster_shards
      )
    end

    SlackNotificationService.new.notify_admin_new_poster(poster: @poster)
  end

  def qr_matches_poster?(qr_content, poster)
    expected_url = poster.referral_url.to_s
    return false if qr_content.blank? || expected_url.blank? || poster.referral_code.blank?

    return true if normalized_url(qr_content) == normalized_url(expected_url)

    qr_uri = parse_http_uri(qr_content)
    expected_uri = parse_http_uri(expected_url)
    return false unless qr_uri && expected_uri

    same_target =
      qr_uri.scheme == expected_uri.scheme &&
      qr_uri.host&.downcase == expected_uri.host&.downcase &&
      normalized_path(qr_uri.path) == normalized_path(expected_uri.path)
    return false unless same_target

    Rack::Utils.parse_nested_query(qr_uri.query)["ref"].to_s.casecmp?(poster.referral_code.to_s)
  end

  def normalized_url(value)
    uri = parse_http_uri(value)
    return value.to_s.strip.downcase.chomp("/") unless uri

    uri.scheme = uri.scheme.downcase
    uri.host = uri.host.downcase
    uri.path = normalized_path(uri.path)
    uri.to_s.chomp("/")
  end

  def parse_http_uri(value)
    uri = URI.parse(value.to_s.strip)
    return unless uri.is_a?(URI::HTTP) && uri.host.present?

    uri
  rescue URI::InvalidURIError
    nil
  end

  def normalized_path(path)
    path.present? ? path : "/"
  end

  def cleanup_temp_file(temp_file)
    return unless temp_file
    temp_file.close
    temp_file.unlink
  rescue => e
    Rails.logger.warn "Failed to cleanup temp file: #{e.message}"
  end
end
