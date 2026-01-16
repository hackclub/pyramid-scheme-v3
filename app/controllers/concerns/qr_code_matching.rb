# frozen_string_literal: true

# Provides QR code matching logic for finding posters by detected QR codes.
# Used by controllers that need to match QR codes to poster records.
module QrCodeMatching
  extend ActiveSupport::Concern

  private

  # Finds a poster matching any of the detected QR codes.
  # @param detected_qr_codes [Array<String>] QR code contents detected from image
  # @param posters [ActiveRecord::Relation] Posters to search within
  # @return [Poster, nil] Matching poster or nil
  def find_matching_poster(detected_qr_codes, posters)
    return nil if detected_qr_codes.empty?

    posters.find do |poster|
      qr_code_matches_poster?(detected_qr_codes, poster)
    end
  end

  # Checks if any detected QR code matches a poster's referral URL or code
  # @param detected_qr_codes [Array<String>] QR code contents
  # @param poster [Poster] Poster to match against
  # @return [Boolean]
  def qr_code_matches_poster?(detected_qr_codes, poster)
    poster_url = poster.referral_url.downcase.chomp("/")
    poster_code = poster.referral_code.downcase

    detected_qr_codes.any? do |qr|
      normalized_qr = qr.to_s.downcase.chomp("/")
      normalized_qr == poster_url || normalized_qr.include?(poster_code)
    end
  end
end
