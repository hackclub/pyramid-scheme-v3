# frozen_string_literal: true

module Admin
  class CampaignAssetsController < BaseController
    before_action :set_campaign
    before_action :set_asset, only: [ :show, :edit, :update, :destroy, :generate_preview ]

    # GET /admin/campaigns/:campaign_id/assets
    def index
      @assets = @campaign.campaign_assets.order(asset_type: :asc, variant: :asc)
      @grouped_assets = @assets.group_by(&:asset_type)
    end

    # GET /admin/campaigns/:campaign_id/assets/new
    def new
      @asset = @campaign.campaign_assets.build
    end

    # POST /admin/campaigns/:campaign_id/assets
    def create
      @asset = @campaign.campaign_assets.build(asset_params)

      if @asset.save
        # If it's a poster template PDF, try to generate preview
        if @asset.poster_template? && @asset.file.attached?
          generate_preview_for_template(@asset)
        end
        redirect_to admin_campaign_assets_path(@campaign), notice: "Asset uploaded successfully."
      else
        render :new, status: :unprocessable_entity
      end
    end

    # GET /admin/campaigns/:campaign_id/assets/:id
    def show
    end

    # GET /admin/campaigns/:campaign_id/assets/:id/edit
    def edit
    end

    # PATCH /admin/campaigns/:campaign_id/assets/:id
    def update
      if @asset.update(asset_params)
        redirect_to admin_campaign_assets_path(@campaign), notice: "Asset updated successfully."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /admin/campaigns/:campaign_id/assets/:id
    def destroy
      @asset.destroy
      redirect_to admin_campaign_assets_path(@campaign), notice: "Asset deleted successfully."
    end

    # POST /admin/campaigns/:campaign_id/assets/:id/generate_preview
    def generate_preview
      unless @asset.poster_template?
        redirect_to admin_campaign_assets_path(@campaign), alert: "Preview generation only available for poster templates."
        return
      end

      begin
        generate_preview_for_template(@asset)
        redirect_to admin_campaign_assets_path(@campaign), notice: "Preview generated successfully."
      rescue => e
        redirect_to admin_campaign_assets_path(@campaign), alert: "Failed to generate preview: #{e.message}"
      end
    end

    private

    def set_campaign
      @campaign = Campaign.find(params[:campaign_id])
    end

    def set_asset
      @asset = @campaign.campaign_assets.find(params[:id])
    end

    def asset_params
      params.require(:campaign_asset).permit(:asset_type, :name, :variant, :description, :active, :file)
    end

    def generate_preview_for_template(asset)
      return unless asset.file.attached? && asset.file.content_type == "application/pdf"

      # Download the PDF to a temp file
      pdf_tempfile = Tempfile.new([ "poster", ".pdf" ])
      pdf_tempfile.binmode
      pdf_tempfile.write(asset.file.download)
      pdf_tempfile.rewind

      # Use vips/imagemagick to convert first page to image
      begin
        preview_path = convert_pdf_to_image(pdf_tempfile.path)

        if preview_path && File.exist?(preview_path)
          # Find or create the preview asset
          preview = @campaign.campaign_assets.find_or_initialize_by(
            asset_type: "poster_preview",
            variant: asset.variant
          )
          preview.name = "#{asset.name} Preview"
          preview.description = "Auto-generated preview from #{asset.name}"
          preview.file.attach(
            io: File.open(preview_path),
            filename: "#{asset.variant || 'poster'}_preview.webp",
            content_type: "image/webp"
          )
          preview.save!

          File.delete(preview_path) if File.exist?(preview_path)
        end
      ensure
        pdf_tempfile.close
        pdf_tempfile.unlink
      end
    end

    def convert_pdf_to_image(pdf_path)
      output_path = "#{pdf_path}.webp"

      # Try using vips first (faster), fallback to imagemagick
      begin
        # Using vips through ruby-vips if available
        if defined?(Vips)
          image = Vips::Image.pdfload(pdf_path, page: 0, dpi: 150)
          image.webpsave(output_path, Q: 85)
        else
          # Fallback to ImageMagick convert command
          system("convert", "-density", "150", "#{pdf_path}[0]", "-quality", "85", output_path)
        end

        File.exist?(output_path) ? output_path : nil
      rescue => e
        Rails.logger.error "Failed to convert PDF to image: #{e.message}"
        nil
      end
    end
  end
end
