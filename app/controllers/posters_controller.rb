# frozen_string_literal: true

class PostersController < ApplicationController
  before_action :set_campaign, only: [ :create ]
  before_action :set_poster, only: [ :show, :edit, :update, :download, :upload_proof, :destroy, :mark_digital, :update_location, :submit ]

  def create
    mark_as_digital = params.dig(:poster, :mark_as_digital) == "1"

    @poster = current_user.posters.build(poster_params.merge(
      campaign: @campaign,
      verification_status: "pending"
    ))

    if @poster.save
      if mark_as_digital
        begin
          @poster.mark_digital!(current_user)
        rescue ActiveRecord::RecordInvalid => e
          Rails.logger.error "Failed to mark poster as digital: #{e.message}"
        end
      end
      respond_to do |format|
        format.html { redirect_to campaign_path(@campaign.slug), notice: "Poster generated! Download it and put it up." }
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "poster_result",
            partial: "posters/created",
            locals: { poster: @poster }
          )
        }
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("poster_result", partial: "posters/error", locals: { poster: @poster }) }
      end
    end
  rescue => e
    Rails.logger.error "Failed to create poster: #{e.class} - #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    @poster ||= Poster.new
    @poster.errors.add(:base, "An unexpected error occurred. Please try again.")

    respond_to do |format|
      format.html {
        if @campaign.present?
          redirect_to campaign_path(@campaign.slug), alert: t("posters.flash.create_error")
        else
          redirect_to root_path, alert: t("posters.flash.create_error")
        end
      }
      format.turbo_stream { render turbo_stream: turbo_stream.replace("poster_result", partial: "posters/error", locals: { poster: @poster }), status: :unprocessable_entity }
    end
  end

  def show
    @qr_data_uri = QrCodeWriterService.new.generate_data_uri(@poster.referral_url, size: 300)
  end

  def edit
  end

  def update
    if params[:proof_image].present?
      handle_proof_upload
    elsif @poster.update(poster_params)
      redirect_to poster_path(@poster), notice: "Poster updated successfully!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def download
    # Call Python proxy service to generate PDF
    proxy_url = ENV.fetch("PROXY_URL", "http://pyramid-proxy:4446")

    # Check if proxy URL is configured
    if proxy_url.include?("pyramid-proxy") && Rails.env.production?
      Rails.logger.error "PROXY_URL not configured for production environment"
      redirect_to campaign_path(@poster.campaign.slug), alert: "Poster generation is temporarily unavailable. Please try again later."
      return
    end

    conn = Faraday.new(url: proxy_url) do |f|
      f.adapter Faraday.default_adapter
    end

    response = conn.post("/generate_poster") do |req|
      req.headers["Content-Type"] = "application/json"
      req.body = {
        content: @poster.referral_url,
        campaign_slug: @poster.campaign.slug,
        style: @poster.poster_type || "color",
        referral_code: @poster.referral_code
      }.to_json
      req.options.timeout = 30
    end

    if response.success?
      send_data response.body,
                type: "application/pdf",
                disposition: "attachment",
                filename: "poster-#{@poster.referral_code}-#{@poster.poster_type}.pdf"
    else
      Rails.logger.error "Failed to generate poster PDF from proxy: #{response.status} - #{response.body}"
      redirect_to campaign_path(@poster.campaign.slug), alert: "Failed to generate poster. Please try again."
    end
  rescue Faraday::ConnectionFailed => e
    Rails.logger.error "Proxy service connection failed (#{proxy_url}): #{e.message}"
    redirect_to campaign_path(@poster.campaign.slug), alert: "Poster generation service is temporarily unavailable. Please try again later."
  rescue => e
    Rails.logger.error "Failed to generate poster PDF: #{e.message}"
    redirect_to campaign_path(@poster.campaign.slug), alert: "Failed to generate poster. Please try again."
  end

  def destroy
    if @poster.verification_status == "pending"
      @poster.destroy
      respond_to do |format|
        format.html { redirect_to campaign_path(@poster.campaign.slug), notice: "Poster deleted successfully." }
        format.turbo_stream {
          render turbo_stream: turbo_stream.remove("poster_#{@poster.id}")
        }
      end
    else
      respond_to do |format|
        format.html { redirect_to campaign_path(@poster.campaign.slug), alert: "Cannot delete a poster that has been submitted for review." }
      end
    end
  end

  def upload_proof
    unless params[:proof_image].present?
      respond_to do |format|
        format.html { redirect_to campaign_path(@poster.campaign.slug), alert: "Please select an image to upload." }
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "proof_upload_result_#{@poster.id}",
            partial: "posters/proof_error",
            locals: { poster: @poster, error: "Please select an image" }
          )
        }
      end
      return
    end

    handle_proof_upload
  end

  def update_location
    unless @poster.location_editable?
      respond_to do |format|
        format.html { redirect_to poster_path(@poster), alert: "Location cannot be changed after proof has been submitted." }
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "location_update_result_#{@poster.id}",
            partial: "posters/location_error",
            locals: { poster: @poster, error: "Location cannot be changed after proof has been submitted" }
          )
        }
      end
      return
    end

    if @poster.update(location_params)
      respond_to do |format|
        format.html { redirect_to poster_path(@poster), notice: "Location updated successfully!" }
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "location_update_result_#{@poster.id}",
            partial: "posters/location_success",
            locals: { poster: @poster }
          )
        }
      end
    else
      respond_to do |format|
        format.html { redirect_to poster_path(@poster), alert: @poster.errors.full_messages.join(", ") }
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "location_update_result_#{@poster.id}",
            partial: "posters/location_error",
            locals: { poster: @poster, error: @poster.errors.full_messages.join(", ") }
          )
        }
      end
    end
  end

  def mark_digital
    if @poster.can_mark_digital?
      @poster.mark_digital!(current_user)

      respond_to do |format|
        format.html {
          if @poster.poster_group.present?
            redirect_to poster_group_path(@poster.poster_group), notice: "Poster marked as digital. Your link is now active!"
          else
            redirect_to campaign_path(@poster.campaign.slug), notice: "Poster marked as digital. Your link is now active!"
          end
        }
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "poster_#{@poster.id}",
            partial: "posters/digital_success",
            locals: { poster: @poster }
          )
        }
      end
    else
      respond_to do |format|
        format.html { redirect_to campaign_path(@poster.campaign.slug), alert: "Cannot mark as digital: poster has proof submitted or is not in pending status." }
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "poster_#{@poster.id}",
            partial: "posters/digital_error",
            locals: { poster: @poster, error: "Cannot mark as digital: poster has proof submitted or is not in pending status." }
          )
        }
      end
    end
  end

  def submit
    # Update location and proof if provided
    if params[:location_description].present?
      @poster.location_description = params[:location_description]
    end

    if params[:proof_image].present?
      @poster.proof_image.attach(params[:proof_image])
    end

    if params[:supporting_evidence].present?
      Array(params[:supporting_evidence]).each do |file|
        @poster.supporting_evidence.attach(file)
      end
    end

    # Save any updates
    unless @poster.save
      respond_to do |format|
        format.html { redirect_to poster_group_path(@poster.poster_group), alert: @poster.errors.full_messages.join(", ") }
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "submit_result_#{@poster.id}",
            partial: "posters/submit_error",
            locals: { error: @poster.errors.full_messages.join(", ") }
          )
        }
      end
      return
    end

    if @poster.verification_status != "pending"
      respond_to do |format|
        format.html { redirect_to poster_group_path(@poster.poster_group), alert: "Poster is not pending submission." }
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "submit_result_#{@poster.id}",
            partial: "posters/submit_error",
            locals: { error: "Poster is not pending submission." }
          )
        }
      end
      return
    end

    # Check has location
    if @poster.location_description.blank?
      respond_to do |format|
        format.html { redirect_to poster_group_path(@poster.poster_group), alert: "Please save your location before submitting. Click 'Save Location' first." }
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "submit_result_#{@poster.id}",
            partial: "posters/submit_error",
            locals: { error: "Please save your location before submitting. Click 'Save Location' first." }
          )
        }
      end
      return
    end

    # Check has proof image
    unless @poster.proof_image.attached?
      respond_to do |format|
        format.html { redirect_to poster_group_path(@poster.poster_group), alert: "Please upload your proof photo before submitting. Click 'Save Proof' first." }
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "submit_result_#{@poster.id}",
            partial: "posters/submit_error",
            locals: { error: "Please upload your proof photo before submitting. Click 'Save Proof' first." }
          )
        }
      end
      return
    end

    # Submit the poster
    @poster.mark_in_review!

    respond_to do |format|
      format.html { redirect_to poster_group_path(@poster.poster_group), notice: "Poster submitted for review!" }
      format.turbo_stream {
        render turbo_stream: turbo_stream.replace(
          "submit_result_#{@poster.id}",
          partial: "posters/submit_success",
          locals: { poster: @poster }
        )
      }
    end
  end

  def handle_poster_link
    code = params[:code]

    if code.length == 8 && code.match?(/^[A-Z0-9]+$/)
      poster = Poster.find_by(referral_code: code)
      if poster
        handle_referral_link(poster)
        return
      end
    end

    poster = Poster.find_by(qr_code_token: code)
    if poster
      handle_qr_scan(poster)
      return
    end

    campaign = Campaign.active.first
    if campaign
      redirect_to campaign_path(campaign.slug)
    else
      redirect_to root_path
    end
  end

  private

  def handle_referral_link(poster)
    poster.record_scan!(
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      country_code: request.headers["CF-IPCountry"],
      metadata: {
        referrer: request.referrer,
        referral_type: "poster_referral"
      }
    )

    session[:referral_code] = poster.referral_code
    session[:referral_type] = "poster"

    redirect_to campaign_path(poster.campaign.slug)
  end

  def handle_qr_scan(poster)
    poster.record_scan!(
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      country_code: request.headers["CF-IPCountry"],
      metadata: {
        referrer: request.referrer,
        referral_type: "qr_scan"
      }
    )

    redirect_to campaign_path(poster.campaign.slug)
  end

  def set_campaign
    campaign_id = params.dig(:poster, :campaign_id) || params[:campaign_id]
    @campaign = Campaign.find_by(id: campaign_id) || current_campaign
  end

  def set_poster
    @poster = current_user.posters.find(params[:id])
  end

  def poster_params
    params.require(:poster).permit(:location_description, :latitude, :longitude, :country_code, :poster_type)
  end

  def location_params
    params.require(:poster).permit(:location_description, :latitude, :longitude)
  end

  def convert_image_if_needed(attachment)
    return unless attachment.attached?

    content_type = attachment.content_type
    return unless content_type.to_s.in?([ "image/heic", "image/heif", "image/x-heic", "image/x-heif" ])

    begin
      require "image_processing/vips"

      converted = ImageProcessing::Vips
        .source(attachment.download)
        .convert("jpg")
        .call

      filename = "#{attachment.filename.base}.jpg"
      attachment.purge
      attachment.attach(io: File.open(converted.path), filename: filename, content_type: "image/jpeg")

      converted.close
      File.unlink(converted.path) if File.exist?(converted.path)
    rescue => e
      Rails.logger.error "Failed to convert HEIC/HEIF image: #{e.message}"
    end
  end

  def auto_verify_proof(poster)
    # Delegate to the service class
    PosterAutoVerificationService.new(poster).call
  end

  def handle_proof_upload
    uploaded_file = params[:proof_image]
    supporting_files = params[:supporting_evidence]
    location_description = params[:location_description]

    # Update location description if provided
    @poster.update(location_description: location_description) if location_description.present?

    @poster.proof_image.attach(uploaded_file) if uploaded_file.present?

    if supporting_files.present?
      supporting_files.each do |file|
        @poster.supporting_evidence.attach(file)
      end
    end

    convert_image_if_needed(@poster.proof_image) if @poster.proof_image.attached?

    # Attempt automatic verification using the qreader microservice
    verification_result = auto_verify_proof(@poster)

    case verification_result
    when :success
      respond_to do |format|
        format.html { redirect_to campaign_path(@poster.campaign.slug), notice: "🎉 Your poster has been automatically verified! Shards have been awarded." }
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "proof_upload_result_#{@poster.id}",
            partial: "posters/proof_success",
            locals: { poster: @poster }
          )
        }
      end
    else # :in_review
      respond_to do |format|
        format.html { redirect_to campaign_path(@poster.campaign.slug), notice: "Proof uploaded! Your poster is now under review." }
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "proof_upload_result_#{@poster.id}",
            partial: "posters/proof_in_review",
            locals: { poster: @poster }
          )
        }
      end
    end
  end
end
