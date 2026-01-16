# frozen_string_literal: true

require "test_helper"

class QrCodeWriterServiceTest < ActiveSupport::TestCase
  setup do
    @service = QrCodeWriterService.new
    @flavortown = campaigns(:flavortown)
    @aces = campaigns(:aces)
    @construct = campaigns(:construct)
  end

  # =============================================================================
  # QR CODE GENERATION
  # =============================================================================
  test "generate_png returns binary data" do
    png_data = @service.generate_png("https://example.com")
    assert png_data.is_a?(String)
    assert png_data.bytesize > 0
    # PNG files start with specific bytes
    assert_equal "\x89PNG".b, png_data[0..3].b
  end

  test "generate_svg returns SVG markup" do
    svg = @service.generate_svg("https://example.com")
    assert svg.include?("<svg")
    assert svg.include?("</svg>")
  end

  test "generate_base64 returns base64 encoded string" do
    base64 = @service.generate_base64("https://example.com")
    # Base64 should only contain valid characters
    assert_match(/^[A-Za-z0-9+\/=]+$/, base64)
    # Should be decodable
    decoded = Base64.strict_decode64(base64)
    assert decoded.bytesize > 0
  end

  test "generate_data_uri returns valid data URI" do
    data_uri = @service.generate_data_uri("https://example.com")
    assert data_uri.start_with?("data:image/png;base64,")
  end

  # =============================================================================
  # QR COORDINATES - CAMPAIGN-SPECIFIC
  # =============================================================================
  test "qr_coordinates_for returns correct coordinates for flavortown color" do
    coords = @service.qr_coordinates_for("flavortown", "color")
    assert_equal 847, coords[:x]
    assert_equal 119, coords[:y]
    assert_equal 258, coords[:size]
  end

  test "qr_coordinates_for returns correct coordinates for flavortown bw" do
    coords = @service.qr_coordinates_for("flavortown", "bw")
    assert_equal 530, coords[:x]
    assert_equal 122, coords[:y]
    assert_equal 218, coords[:size]
  end

  test "qr_coordinates_for returns correct coordinates for aces" do
    coords = @service.qr_coordinates_for("aces", "color")
    assert_equal 857, coords[:x]
    assert_equal 148, coords[:y]
    assert_equal 226, coords[:size]
  end

  test "qr_coordinates_for returns correct coordinates for construct" do
    coords = @service.qr_coordinates_for("construct", "color")
    assert_equal 20, coords[:x]
    assert_equal 132, coords[:y]
    assert_equal 175, coords[:size]
  end

  test "qr_coordinates_for falls back to flavortown for unknown campaign" do
    coords = @service.qr_coordinates_for("unknown_campaign", "color")
    flavortown_coords = @service.qr_coordinates_for("flavortown", "color")
    assert_equal flavortown_coords, coords
  end

  test "qr_coordinates_for falls back to color for unknown style" do
    coords = @service.qr_coordinates_for("flavortown", "unknown_style")
    color_coords = @service.qr_coordinates_for("flavortown", "color")
    assert_equal color_coords, coords
  end

  # =============================================================================
  # REFERRAL CODE COORDINATES
  # =============================================================================
  test "referral_code_coordinates_for returns text config" do
    coords = @service.referral_code_coordinates_for("flavortown", "color")
    assert coords.key?(:x)
    assert coords.key?(:y)
    assert coords.key?(:size)
    assert coords.key?(:color)
  end

  test "referral_code_coordinates_for varies by style" do
    color_coords = @service.referral_code_coordinates_for("flavortown", "color")
    bw_coords = @service.referral_code_coordinates_for("flavortown", "bw")

    # Colors should be different for visibility
    assert_not_equal color_coords[:color], bw_coords[:color]
  end
end
