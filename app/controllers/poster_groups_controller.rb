# frozen_string_literal: true

class PosterGroupsController < ApplicationController
  include QrCodeMatching

  before_action :set_campaign, only: [ :create ]
  before_action :set_poster_group, only: [ :show, :update, :destroy, :submit_all, :auto_detect, :download_all ]

  def create
    count = params.dig(:poster_group, :count).to_i
    count = [ count, PosterGroup::MAX_POSTERS_PER_GROUP ].min
    count = [ count, 1 ].max

    # Calculate how many will be paid vs unpaid
    remaining_quota = current_user.remaining_paid_posters_this_week
    paid_count = [ count, remaining_quota ].min
    unpaid_count = count - paid_count

    # Single poster: create as standalone (not in a group)
    if count == 1
      create_single_poster(paid_count, unpaid_count)
      return
    end

    # Multiple posters: create as a group
    @poster_group = current_user.poster_groups.build(
      campaign: @campaign,
      name: poster_group_params[:name],
      charset: poster_group_params[:charset]
    )

    if @poster_group.save
      begin
        @poster_group.generate_posters!(
          count: count,
          poster_type: poster_group_params[:poster_type] || "color"
        )

        respond_to do |format|
          format.html { redirect_to campaign_path(@campaign.slug), notice: "#{count} posters generated successfully!" }
          format.turbo_stream {
            render turbo_stream: turbo_stream.replace(
              "poster_result",
              partial: "poster_groups/created",
              locals: { poster_group: @poster_group, paid_count: paid_count, unpaid_count: unpaid_count }
            )
          }
        end
      rescue PosterGroup::QuotaExceededError => e
        @poster_group.destroy
        respond_to do |format|
          format.html { redirect_to campaign_path(@campaign.slug), alert: e.message }
          format.turbo_stream {
            render turbo_stream: turbo_stream.replace(
              "poster_result",
              partial: "poster_groups/error",
              locals: { error: e.message }
            )
          }
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to campaign_path(@campaign.slug), alert: "Failed to create poster group." }
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "poster_result",
            partial: "poster_groups/error",
            locals: { error: @poster_group.errors.full_messages.join(", ") }
          )
        }
      end
    end
  end

  def show
    @posters = @poster_group.posters.order(created_at: :asc)
  end

  def download_all
    # Handle zip format
    if params[:format] == "zip"
      return download_all_zip
    end

    # Call Python proxy service to generate batch PDF (merged)
    proxy_url = ENV.fetch("PROXY_URL", "http://pyramid-proxy:4446")

    # Check if proxy URL is configured for production
    if proxy_url.include?("pyramid-proxy") && Rails.env.production?
      Rails.logger.error "PROXY_URL not configured for production environment"
      redirect_to poster_group_path(@poster_group), alert: "Poster generation is temporarily unavailable. Please try again later."
      return
    end

    posters_data = @poster_group.posters.map do |poster|
      {
        content: poster.referral_url,
        referral_code: poster.referral_code,
        poster_type: poster.poster_type || "color"
      }
    end

    conn = Faraday.new(url: proxy_url) do |f|
      f.adapter Faraday.default_adapter
    end

    response = conn.post("/generate_poster_batch") do |req|
      req.headers["Content-Type"] = "application/json"
      req.body = {
        posters: posters_data,
        campaign_slug: @poster_group.campaign.slug
      }.to_json
      req.options.timeout = 60  # Longer timeout for batch generation
    end

    if response.success?
      group_name = @poster_group.name.presence || "group_#{@poster_group.id}"
      send_data response.body,
                type: "application/pdf",
                disposition: "attachment",
                filename: "posters_#{group_name.parameterize}.pdf"
    else
      Rails.logger.error "Failed to generate bulk poster download from proxy: #{response.status} - #{response.body}"
      redirect_to poster_group_path(@poster_group), alert: "Failed to generate posters. Please try again."
    end
  rescue Faraday::ConnectionFailed => e
    Rails.logger.error "Proxy service connection failed (#{proxy_url}): #{e.message}"
    redirect_to poster_group_path(@poster_group), alert: "Poster generation service is temporarily unavailable. Please try again later."
  rescue => e
    Rails.logger.error "Failed to generate bulk poster download: #{e.message}"
    redirect_to poster_group_path(@poster_group), alert: "Failed to generate posters. Please try again."
  end

  def download_all_zip
    proxy_url = ENV.fetch("PROXY_URL", "http://pyramid-proxy:4446")

    # Check if proxy URL is configured for production
    if proxy_url.include?("pyramid-proxy") && Rails.env.production?
      Rails.logger.error "PROXY_URL not configured for production environment"
      redirect_to poster_group_path(@poster_group), alert: "Poster generation is temporarily unavailable. Please try again later."
      return
    end

    conn = Faraday.new(url: proxy_url) do |f|
      f.adapter Faraday.default_adapter
    end

    # Call Python proxy service to generate batch ZIP
    posters_data = @poster_group.posters.map do |poster|
      {
        content: poster.referral_url,
        referral_code: poster.referral_code,
        poster_type: poster.poster_type || "color"
      }
    end

    response = conn.post("/generate_poster_batch_zip") do |req|
      req.headers["Content-Type"] = "application/json"
      req.body = {
        posters: posters_data,
        campaign_slug: @poster_group.campaign.slug
      }.to_json
      req.options.timeout = 120  # Longer timeout for batch generation
    end

    if response.success?
      group_name = @poster_group.name.presence || "group_#{@poster_group.id}"
      send_data response.body,
                type: "application/zip",
                disposition: "attachment",
                filename: "posters_#{group_name.parameterize}.zip"
    else
      Rails.logger.error "Failed to generate zip from proxy: #{response.status} - #{response.body}"
      redirect_to poster_group_path(@poster_group), alert: "Failed to generate posters. Please try again."
    end
  rescue Faraday::ConnectionFailed => e
    Rails.logger.error "Proxy service connection failed (#{proxy_url}): #{e.message}"
    redirect_to poster_group_path(@poster_group), alert: "Poster generation service is temporarily unavailable. Please try again later."
  rescue => e
    Rails.logger.error "Failed to generate zip download: #{e.message}"
    redirect_to poster_group_path(@poster_group), alert: "Failed to generate posters. Please try again."
  end

  def update
    if @poster_group.update(poster_group_params.slice(:name))
      redirect_to poster_group_path(@poster_group), notice: "Group updated successfully!"
    else
      redirect_to poster_group_path(@poster_group), alert: "Failed to update group."
    end
  end

  def destroy
    # Only allow deletion if all posters are pending
    if @poster_group.has_submitted_posters?
      redirect_to campaign_path(@poster_group.campaign.slug), alert: "Cannot delete group with submitted posters."
      return
    end

    @poster_group.posters.destroy_all
    @poster_group.destroy
    redirect_to campaign_path(@poster_group.campaign.slug), notice: "Poster group deleted."
  end

  # Submit all posters in the group at once
  def submit_all
    posters_to_submit = @poster_group.posters.pending

    if posters_to_submit.empty?
      redirect_to poster_group_path(@poster_group), alert: "No pending posters to submit."
      return
    end

    # Check all have locations
    missing_location = posters_to_submit.where(location_description: [ nil, "" ])
    if missing_location.exists?
      redirect_to poster_group_path(@poster_group), alert: "All posters must have a location before submitting."
      return
    end

    # Check all have proof images
    posters_without_proof = posters_to_submit.select { |p| !p.proof_image.attached? }
    if posters_without_proof.any?
      redirect_to poster_group_path(@poster_group), alert: "All posters must have proof images before submitting."
      return
    end

    # Submit all posters
    posters_to_submit.each do |poster|
      poster.mark_in_review!
    end

    redirect_to campaign_path(@poster_group.campaign.slug), notice: "All #{posters_to_submit.count} posters submitted for review!"
  end

  # Auto-detect which poster a proof image belongs to within this group
  def auto_detect
    unless params[:proof_image].present?
      respond_to do |format|
        format.html { redirect_to poster_group_path(@poster_group), alert: "Please select an image." }
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "auto_detect_result",
            partial: "poster_groups/auto_detect_error",
            locals: { error: "No image selected. Please upload a photo of your poster." }
          )
        }
      end
      return
    end

    # Try to detect QR code from the uploaded image
    temp_file = nil
    begin
      uploaded_file = params[:proof_image]
      temp_file = Tempfile.new([ "proof", ".jpg" ])
      temp_file.binmode
      temp_file.write(uploaded_file.read)
      uploaded_file.rewind
      temp_file.rewind

      # Use QR reader service to detect codes
      qr_reader = QrCodeReaderService.new
      detected_qr_codes = qr_reader.read_from_file(temp_file.path)

      if detected_qr_codes.empty?
        # No QR detected - submit to first pending poster for manual review
        handle_no_qr_detected(uploaded_file)
        return
      end

      # Try to match to a poster in THIS group only
      matched_poster = find_matching_poster_in_group(detected_qr_codes)

      if matched_poster
        handle_group_match(matched_poster, uploaded_file)
      else
        # Check if it matches a poster outside this group (user's other posters)
        matched_outside = find_matching_poster_outside_group(detected_qr_codes)
        if matched_outside
          handle_wrong_group_error(matched_outside, detected_qr_codes)
        else
          # QR detected but no match - show clear error message
          handle_qr_no_match(uploaded_file, detected_qr_codes)
        end
      end
    rescue QrCodeReaderService::QrReaderError => e
      Rails.logger.error "QR Reader error in auto_detect: #{e.message}"
      handle_qr_reader_error(uploaded_file, e)
    rescue => e
      Rails.logger.error "Error in auto_detect: #{e.message}"
      handle_general_error(e)
    ensure
      if temp_file
        temp_file.close
        temp_file.unlink
      end
    end
  end

  private

  def set_campaign
    campaign_id = params.dig(:poster_group, :campaign_id) || params[:campaign_id]
    @campaign = Campaign.find_by(id: campaign_id) || current_campaign
  end

  def set_poster_group
    @poster_group = current_user.poster_groups.find(params[:id])
  end

  def poster_group_params
    params.require(:poster_group).permit(:name, :charset, :count, :poster_type, :campaign_id, :mark_as_digital, :location_description)
  end

  def quota_exceeded_message(requested, remaining)
    "Cannot generate #{requested} posters. You have #{remaining} paid posters remaining this week. " \
    "You can still generate more posters, but they will not earn shards. You can also repeatedly print any existing poster."
  end

  # Create a single standalone poster (not in a group)
  def create_single_poster(paid_count, unpaid_count)
    mark_as_digital = poster_group_params[:mark_as_digital] == "1"
    location = poster_group_params[:location_description]

    @poster = current_user.posters.build(
      campaign: @campaign,
      poster_type: poster_group_params[:poster_type] || "color",
      verification_status: "pending"
    )

    if @poster.save
      # Mark as digital if requested
      if mark_as_digital
        begin
          @poster.mark_digital!(current_user)
          @poster.update(location_description: location) if location.present?
          @poster.reload
        rescue ActiveRecord::RecordInvalid => e
          Rails.logger.error "Failed to mark poster as digital: #{e.message}"
        end
      end

      respond_to do |format|
        if mark_as_digital && @poster.verification_status == "digital"
          format.html { redirect_to campaign_path(@campaign.slug), notice: "Digital poster activated! Your link is ready to share." }
          format.turbo_stream {
            render turbo_stream: turbo_stream.replace(
              "poster_result",
              partial: "posters/digital_success",
              locals: { poster: @poster }
            )
          }
        else
          format.html { redirect_to campaign_path(@campaign.slug), notice: "Poster generated successfully!" }
          format.turbo_stream {
            render turbo_stream: turbo_stream.replace(
              "poster_result",
              partial: "posters/created",
              locals: { poster: @poster, paid_count: paid_count, unpaid_count: unpaid_count }
            )
          }
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to campaign_path(@campaign.slug), alert: "Failed to create poster." }
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "poster_result",
            partial: "poster_groups/error",
            locals: { error: @poster.errors.full_messages.join(", ") }
          )
        }
      end
    end
  end

  # Auto-detect helpers - use QrCodeMatching concern for matching logic
  def find_matching_poster_in_group(detected_qr_codes)
    find_matching_poster(detected_qr_codes, @poster_group.posters.pending)
  end

  def find_matching_poster_outside_group(detected_qr_codes)
    # Look in user's other posters not in this group
    find_matching_poster(detected_qr_codes, current_user.posters.where.not(poster_group_id: @poster_group.id))
  end

  def handle_group_match(poster, uploaded_file)
    poster.proof_image.attach(uploaded_file)
    poster.update(location_description: params[:location_description]) if params[:location_description].present?

    # Handle supporting evidence if provided
    if params[:supporting_evidence].present?
      params[:supporting_evidence].each do |file|
        poster.supporting_evidence.attach(file)
      end
    end

    # Auto-verify
    verification_result = PosterAutoVerificationService.new(poster).call

    respond_to do |format|
      format.html { redirect_to poster_group_path(@poster_group), notice: "Poster ##{poster.id} matched and submitted!" }
      format.turbo_stream {
        render turbo_stream: turbo_stream.replace(
          "auto_detect_result",
          partial: "poster_groups/auto_detect_success",
          locals: { poster: poster, verification_result: verification_result }
        )
      }
    end
  end

  def handle_wrong_group_error(matched_poster, detected_qr_codes)
    if matched_poster.poster_group.present?
      group_name = matched_poster.poster_group.name.presence || "Poster Group ##{matched_poster.poster_group.id}"
      error_msg = "This QR code belongs to poster ##{matched_poster.id} in \"#{group_name}\", not this group."
    else
      error_msg = "This QR code belongs to poster ##{matched_poster.id} (standalone poster), not this group."
    end

    respond_to do |format|
      format.html { redirect_to poster_group_path(@poster_group), alert: error_msg }
      format.turbo_stream {
        render turbo_stream: turbo_stream.replace(
          "auto_detect_result",
          partial: "poster_groups/auto_detect_wrong_group",
          locals: { matched_poster: matched_poster, detected_qr_codes: detected_qr_codes }
        )
      }
    end
  end

  def handle_no_qr_detected(uploaded_file)
    # No QR code detected - reject the upload with error
    respond_to do |format|
      format.html { redirect_to poster_group_path(@poster_group), alert: "No valid QR code detected in the image. Please upload a clear photo of your poster with the QR code visible." }
      format.turbo_stream {
        render turbo_stream: turbo_stream.replace(
          "auto_detect_result",
          partial: "poster_groups/auto_detect_error",
          locals: { error: "No valid QR code detected in the image. Please upload a clear photo of your poster with the QR code visible." }
        )
      }
    end
  end

  def handle_qr_no_match(uploaded_file, detected_qr_codes)
    # QR detected but doesn't match any poster - show clear error
    poster = @poster_group.posters.pending.first
    unless poster
      qr_display = detected_qr_codes.first.to_s[0..11]
      respond_to do |format|
        format.html { redirect_to poster_group_path(@poster_group), alert: "QR code detected (#{qr_display}) but doesn't match any poster in this group." }
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "auto_detect_result",
            partial: "poster_groups/auto_detect_no_match",
            locals: { detected_qr_codes: detected_qr_codes, poster: nil }
          )
        }
      end
      return
    end

    poster.proof_image.attach(uploaded_file)
    poster.metadata ||= {}
    poster.metadata["detected_qr_codes"] = detected_qr_codes
    poster.update(location_description: params[:location_description]) if params[:location_description].present?
    poster.mark_in_review!

    respond_to do |format|
      format.html { redirect_to poster_group_path(@poster_group), notice: "Submitted for manual review (QR doesn't match group posters)." }
      format.turbo_stream {
        render turbo_stream: turbo_stream.replace(
          "auto_detect_result",
          partial: "poster_groups/auto_detect_no_match",
          locals: { detected_qr_codes: detected_qr_codes, poster: poster }
        )
      }
    end
  end

  def handle_qr_reader_error(uploaded_file, error)
    # Service error - submit for manual review
    poster = @poster_group.posters.pending.first
    if poster
      poster.proof_image.attach(uploaded_file)
      poster.update(location_description: params[:location_description]) if params[:location_description].present?
      poster.mark_in_review!
    end

    respond_to do |format|
      format.html { redirect_to poster_group_path(@poster_group), notice: "Submitted for manual review." }
      format.turbo_stream {
        render turbo_stream: turbo_stream.replace(
          "auto_detect_result",
          partial: "poster_groups/auto_detect_manual_review",
          locals: { poster: poster, reason: "QR detection service unavailable" }
        )
      }
    end
  end

  def handle_general_error(error)
    Rails.logger.error "General error in auto_detect: #{error.class} - #{error.message}\n#{error.backtrace.first(5).join("\n")}"

    respond_to do |format|
      format.html { redirect_to poster_group_path(@poster_group), alert: "An error occurred while processing your image. Please try again." }
      format.turbo_stream {
        render turbo_stream: turbo_stream.replace(
          "auto_detect_result",
          partial: "poster_groups/auto_detect_error",
          locals: { error: "An unexpected error occurred while processing the image. Please try again or contact support if the issue persists." }
        )
      }
    end
  end
end
