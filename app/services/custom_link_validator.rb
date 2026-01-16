# frozen_string_literal: true

# Validates custom referral link format, uniqueness, and content.
# Extracted from CustomLinksController to DRY up validation logic
# shared between update and validate endpoints.
class CustomLinkValidator
  Result = Struct.new(:valid?, :errors, keyword_init: true)

  def initialize(code:, user:, check_moderation: false)
    @code = code.to_s.strip
    @user = user
    @check_moderation = check_moderation
  end

  # Performs basic format validation (fast, no external calls)
  # @return [Result]
  def validate_format
    errors = []

    # Check format (only letters a-z, A-Z)
    unless @code.match?(/\A[a-zA-Z]+\z/)
      errors << "Must contain only letters (a-z, A-Z)"
    end

    # Check max length
    if @code.length > 64
      errors << "Must be 64 characters or less"
    end

    # Check minimum length
    if @code.length < 3 && @code.length.positive?
      errors << "Must be at least 3 characters"
    end

    Result.new(valid?: errors.empty?, errors: errors)
  end

  # Performs full validation including uniqueness and blocked words
  # @return [Result]
  def validate_full
    format_result = validate_format
    return format_result unless format_result.valid?

    errors = []

    # Check if blocked by YSWS service
    if blocked_by_ysws?
      errors << "This link is reserved"
    end

    # Check if taken by another user
    if taken_by_other_user?
      errors << "Already taken"
    end

    Result.new(valid?: errors.empty?, errors: errors)
  end

  # Performs complete validation including AI moderation
  # @return [Result]
  def validate_with_moderation
    full_result = validate_full
    return full_result unless full_result.valid?

    errors = []

    begin
      moderation_result = AiModerationService.moderate(@code)
      if moderation_result.flagged?
        errors << "This custom link was flagged for review. Please choose a different one."
      end
    rescue StandardError => e
      Rails.logger.error "AI moderation error: #{e.message}"
      errors << "Moderation service unavailable. Please try again later."
    end

    Result.new(valid?: errors.empty?, errors: errors)
  end

  private

  def blocked_by_ysws?
    YswsBlockedWordsService.blocked?(@code)
  rescue StandardError => e
    Rails.logger.warn "YswsBlockedWordsService error: #{e.message}"
    false # Don't block if service is down
  end

  def taken_by_other_user?
    User.where.not(id: @user.id)
        .where("LOWER(custom_referral_code) = ? OR LOWER(referral_code) = ?",
               @code.downcase, @code.downcase)
        .exists?
  end
end
