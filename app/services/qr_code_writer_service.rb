# frozen_string_literal: true

require "rqrcode"
require "prawn"
require "combine_pdf"

# Generates QR codes in various formats and creates poster PDFs with embedded QR codes.
#
# Supports generating QR codes as PNG, SVG, Base64, or data URIs. Also handles
# overlaying QR codes onto PDF poster templates with campaign-specific positioning.
#
# @example Generate a QR code PNG
#   writer = QrCodeWriterService.new
#   png_data = writer.generate_png("https://example.com/ref/ABC")
#
# @example Generate a poster PDF with QR code
#   writer = QrCodeWriterService.new
#   pdf_data = writer.generate_qr_pdf(
#     content: "https://example.com/scan?p=123",
#     campaign: campaign,
#     referral_code: "ABC123"
#   )
class QrCodeWriterService
  class PdfGenerationError < StandardError; end

  # Default QR code generation settings
  DEFAULT_QR_SIZE = 300
  DEFAULT_MODULE_SIZE = 6
  DEFAULT_BORDER_MODULES = 4

  # Generates a QR code as PNG binary data.
  #
  # @param content [String] The content to encode in the QR code
  # @param size [Integer] The output image size in pixels
  # @return [String] Binary PNG data
  def generate_png(content, size: DEFAULT_QR_SIZE)
    qr = RQRCode::QRCode.new(content)

    qr.as_png(
      bit_depth: 1,
      border_modules: DEFAULT_BORDER_MODULES,
      color_mode: ChunkyPNG::COLOR_GRAYSCALE,
      color: "black",
      file: nil,
      fill: "white",
      module_px_size: DEFAULT_MODULE_SIZE,
      resize_exactly_to: size,
      resize_gte_to: false
    ).to_s
  end

  # Generates a QR code as SVG.
  #
  # @param content [String] The content to encode in the QR code
  # @param size [Integer] The output image size in pixels
  # @return [String] SVG markup
  def generate_svg(content, size: DEFAULT_QR_SIZE)
    qr = RQRCode::QRCode.new(content)

    qr.as_svg(
      color: "000",
      shape_rendering: "crispEdges",
      module_size: DEFAULT_MODULE_SIZE,
      standalone: true,
      use_path: true,
      viewbox: true,
      svg_attributes: {
        width: size,
        height: size
      }
    )
  end

  # Generates a QR code as Base64-encoded PNG for HTML embedding.
  #
  # @param content [String] The content to encode in the QR code
  # @param size [Integer] The output image size in pixels
  # @return [String] Base64-encoded PNG data
  def generate_base64(content, size: DEFAULT_QR_SIZE)
    png_data = generate_png(content, size: size)
    Base64.strict_encode64(png_data)
  end

  # Generates a data URI for embedding in an img src attribute.
  #
  # @param content [String] The content to encode in the QR code
  # @param size [Integer] The output image size in pixels
  # @return [String] Data URI (data:image/png;base64,...)
  def generate_data_uri(content, size: DEFAULT_QR_SIZE)
    base64 = generate_base64(content, size: size)
    "data:image/png;base64,#{base64}"
  end

  # Generate a poster PDF with QR code embedded at specified coordinates
  # @param template_path [String] Path to the PDF template file
  # @param content [String] The content to encode in the QR code (poster ID + user ID + location)
  # @param x [Float] X coordinate in points (from left edge)
  # @param y [Float] Y coordinate in points (from bottom edge)
  # @param qr_size [Float] Size of the QR code in points
  # @param page [Integer] Page number to place QR code on (1-indexed)
  # @param referral_code [String, nil] Optional referral code to print on poster
  # @param text_config [Hash, nil] Optional text configuration for referral code
  # @return [String] Binary PDF data
  def generate_poster_pdf(template_path:, content:, x:, y:, qr_size: 100, page: 1, referral_code: nil, text_config: nil)
    raise PdfGenerationError, "Template file not found: #{template_path}" unless File.exist?(template_path)

    qr_png_data = generate_png(content, size: qr_size.to_i * 3)

    qr_overlay = create_qr_overlay_pdf(
      qr_png_data: qr_png_data,
      x: x,
      y: y,
      qr_size: qr_size,
      template_path: template_path,
      referral_code: referral_code,
      text_config: text_config
    )

    template_pdf = CombinePDF.load(template_path)
    overlay_pdf = CombinePDF.parse(qr_overlay)

    page_index = page - 1
    if template_pdf.pages[page_index]
      template_pdf.pages[page_index] << overlay_pdf.pages[0]
    else
      raise PdfGenerationError, "Page #{page} does not exist in template"
    end

    template_pdf.to_pdf
  end

  # Generate a new PDF with QR code overlaid on template
  # @param content [String] The content to encode in the QR code
  # @param x [Float] X coordinate in points (not used with templates)
  # @param y [Float] Y coordinate in points (not used with templates)
  # @param qr_size [Float] Size of the QR code in points (not used with templates)
  # @param page_size [Symbol] Page size (e.g., :A4, :LETTER)
  # @param style [String] Poster style (color, bw, printer_efficient)
  # @param campaign [Campaign, nil] Campaign to use for template selection
  # @param referral_code [String, nil] Optional referral code to print on poster
  # @return [String] Binary PDF data
  # @raise [ArgumentError] if campaign is nil
  def generate_qr_pdf(content:, x: 50, y: 50, qr_size: 150, page_size: :A4, style: "color", campaign: nil, referral_code: nil)
    raise ArgumentError, "Campaign is required for poster PDF generation" if campaign.nil?

    campaign_slug = campaign.slug

    # Determine template path based on campaign
    template_filename = case style
    when "bw" then "poster-bw.pdf"
    when "printer_efficient" then "poster-printer_efficient.pdf"
    else "poster-color.pdf"
    end
    template_path = Rails.root.join("app", "assets", "images", campaign_slug, template_filename)

    # Fall back to default campaign template if campaign-specific template doesn't exist
    default_campaign_slug = ENV.fetch("DEFAULT_CAMPAIGN_SLUG", "flavortown")
    unless File.exist?(template_path)
      template_path = Rails.root.join("app", "assets", "images", default_campaign_slug, template_filename)
    end

    if File.exist?(template_path)
      # Get QR coordinates for this campaign and style
      qr_config = qr_coordinates_for(campaign_slug, style)
      # Get referral code text coordinates for this campaign and style
      text_config = referral_code_coordinates_for(campaign_slug, style)

      generate_poster_pdf(
        template_path: template_path.to_s,
        content: content,
        x: qr_config[:x],
        y: qr_config[:y],
        qr_size: qr_config[:size],
        referral_code: referral_code,
        text_config: text_config
      )
    else
      # Fallback: simple QR on white if template doesn't exist yet
      qr_png_data = generate_png(content, size: 600)

      Prawn::Document.new(page_size: page_size, margin: 0) do |pdf|
        temp_qr_file = Tempfile.new([ "qr", ".png" ])
        begin
          temp_qr_file.binmode
          temp_qr_file.write(qr_png_data)
          temp_qr_file.rewind

          pdf.image temp_qr_file.path, at: [ (pdf.bounds.width - 200) / 2, pdf.bounds.height / 2 + 100 ], width: 200, height: 200
          pdf.text_box "Scan to join", at: [ 0, pdf.bounds.height / 2 - 120 ], width: pdf.bounds.width, align: :center, size: 14
        ensure
          temp_qr_file.close
          temp_qr_file.unlink
        end
      end.render
    end
  end

  # QR code coordinates for each campaign and style
  # PDF dimensions vary by campaign; y is from bottom edge
  # Flavortown: 1190x1684 points
  # Construct: 842.25x1199 points (A3)
  def qr_coordinates_for(campaign_slug, style)
    coords = {
      "flavortown" => {
        "color" => { x: 847, y: 119, size: 258 },
        "bw" => { x: 530, y: 122, size: 218 },
        "printer_efficient" => { x: 847, y: 119, size: 258 }
      },
      "sleepover" => {
        "color" => { x: 1133, y: 71, size: 326 },
        "bw" => { x: 1144, y: 81, size: 299 },
        "printer_efficient" => { x: 1149, y: 82, size: 318 }
      },
      "aces" => {
        "color" => { x: 857, y: 148, size: 226 },
        "bw" => { x: 115, y: 175, size: 230 },
        "printer_efficient" => { x: 857, y: 148, size: 226 }
      },
      "construct" => {
        # A4 poster (595.5x842.25 points), QR in bottom-left dashed box
        # Box bounds: x=15.5-200, y=127-312.5 (from bottom) (~185x185 pts)
        # QR centered in box with padding
        "color" => { x: 20, y: 132, size: 175 },
        "bw" => { x: 20, y: 132, size: 175 },
        "printer_efficient" => { x: 20, y: 132, size: 175 }
      }
    }

    campaign_coords = coords[campaign_slug] || coords["flavortown"]
    campaign_coords[style] || campaign_coords["color"]
  end

  # Referral code text coordinates for each campaign and style
  # Positioned below the "flavortown.hackclub.com" text on flavortown posters
  # y is from bottom edge, text is centered at x
  def referral_code_coordinates_for(campaign_slug, style)
    coords = {
      "flavortown" => {
        "color" => { x: 595, y: 62, size: 18, color: "FFFFFF" },
        "bw" => { x: 595, y: 62, size: 18, color: "000000" },
        "printer_efficient" => { x: 595, y: 62, size: 18, color: "FFFFFF" }
      },
      "aces" => {
        "color" => { x: 595, y: 55, size: 16, color: "8B1A1A" },
        "bw" => { x: 880, y: 55, size: 16, color: "000000" },
        "printer_efficient" => { x: 595, y: 55, size: 16, color: "8B1A1A" }
      },
      "construct" => {
        # Below QR code in the dashed box, centered
        "color" => { x: 108, y: 120, size: 12, color: "000000" },
        "bw" => { x: 108, y: 120, size: 12, color: "000000" },
        "printer_efficient" => { x: 108, y: 120, size: 12, color: "000000" }
      }
    }

    campaign_coords = coords[campaign_slug] || coords["flavortown"]
    campaign_coords[style] || campaign_coords["color"]
  end

  # Build QR code content string for a poster
  # @param poster_id [String, Integer] The poster's unique identifier
  # @param user_id [String, Integer] The user's unique identifier
  # @param location [String, nil] Optional location identifier
  # @return [String] Encoded content for QR code
  def build_poster_qr_content(poster_id:, user_id:, location: nil)
    base_url = Pyramid.base_url
    params = { p: poster_id, u: user_id }
    params[:l] = location if location.present?

    "#{base_url}/scan?#{params.to_query}"
  end

  private

  def create_qr_overlay_pdf(qr_png_data:, x:, y:, qr_size:, template_path:, referral_code: nil, text_config: nil)
    template_pdf = CombinePDF.load(template_path)
    first_page = template_pdf.pages.first
    page_width = first_page[:MediaBox][2]
    page_height = first_page[:MediaBox][3]

    Prawn::Document.new(page_size: [ page_width, page_height ], margin: 0) do |pdf|
      temp_qr_file = Tempfile.new([ "qr", ".png" ])
      begin
        temp_qr_file.binmode
        temp_qr_file.write(qr_png_data)
        temp_qr_file.rewind

        pdf.image temp_qr_file.path, at: [ x, y + qr_size ], width: qr_size, height: qr_size

        # Add referral code text if provided
        if referral_code.present? && text_config.present?
          text_x = text_config[:x]
          text_y = text_config[:y]
          text_size = text_config[:size] || 18
          text_color = text_config[:color] || "000000"

          pdf.fill_color text_color
          pdf.font_size text_size
          pdf.text_box "Ref: #{referral_code}",
                       at: [ 0, text_y + text_size ],
                       width: page_width,
                       height: text_size + 4,
                       align: :center,
                       valign: :center,
                       style: :bold
        end
      ensure
        temp_qr_file.close
        temp_qr_file.unlink
      end
    end.render
  end
end
