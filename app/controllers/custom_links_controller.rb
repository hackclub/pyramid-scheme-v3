# frozen_string_literal: true

class CustomLinksController < ApplicationController
  before_action :set_user

  def update
    new_code = params[:custom_link].to_s.strip

    # Validate format first (fast checks)
    validator = CustomLinkValidator.new(code: new_code, user: @user)
    format_result = validator.validate_format
    unless format_result.valid?
      return render_validation_error(format_result.errors.first)
    end

    # Full validation including uniqueness
    full_result = validator.validate_full
    unless full_result.valid?
      return render_validation_error(full_result.errors.first)
    end

    # AI moderation check
    moderation_result = validator.validate_with_moderation
    unless moderation_result.valid?
      status = moderation_result.errors.first.include?("unavailable") ? :service_unavailable : :unprocessable_entity
      return render json: { success: false, error: moderation_result.errors.first }, status: status
    end

    # Check if user can afford the change
    unless @user.can_change_custom_referral_code?
      return render_validation_error("Not enough shards. You need #{User::CUSTOM_REFERRAL_CODE_CHANGE_COST} shards to change your custom link.")
    end

    # All validations passed, update the custom link
    perform_custom_link_update(new_code)
  end

  def validate
    new_code = params[:custom_link].to_s.strip

    validator = CustomLinkValidator.new(code: new_code, user: @user)
    result = validator.validate_full

    render json: {
      valid: result.valid?,
      errors: result.errors
    }
  rescue StandardError => e
    Rails.logger.error "Custom link validation error: #{e.message}"
    render json: {
      valid: false,
      errors: [ "Validation service unavailable. Please try again." ]
    }, status: :service_unavailable
  end

  private

  def set_user
    @user = current_user
  end

  def render_validation_error(error)
    render json: { success: false, error: error }, status: :unprocessable_entity
  end

  def perform_custom_link_update(new_code)
    cost = @user.custom_referral_code_change_cost
    @user.set_custom_referral_code!(new_code)

    render json: {
      success: true,
      message: cost.positive? ? "Custom link updated! #{cost} shards deducted." : "Custom link set!",
      custom_link: new_code,
      new_balance: @user.reload.total_shards
    }
  rescue User::InsufficientShardsError => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: {
      success: false,
      error: e.record.errors.full_messages.join(", ")
    }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error "Custom link update error: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: {
      success: false,
      error: "An error occurred while updating your custom link. Please try again."
    }, status: :internal_server_error
  end
end
