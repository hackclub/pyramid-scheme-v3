# frozen_string_literal: true

# Shared region determination logic for shop-related controllers.
# Extracts duplicated determine_user_region method from ShopController
# and ShopOrdersController.
module Regionable
  extend ActiveSupport::Concern

  included do
    helper_method :user_region if respond_to?(:helper_method)
  end

  private

  # Determines the user's region for pricing purposes.
  # Priority: saved preference > country code > timezone cookie > default
  #
  # @return [String] Region code (e.g., "US", "EU", "XX")
  def determine_user_region
    # Use saved preference if available
    if current_user&.region.present?
      return current_user.region if Shop::Regionalizable::REGION_CODES.include?(current_user.region)
    end

    # Try to infer from user's country
    if current_user&.country_code.present?
      region = Shop::Regionalizable.country_to_region(current_user.country_code)
      return region if region != "XX"
    end

    # Try timezone from cookie
    if cookies[:timezone].present?
      region = Shop::Regionalizable.timezone_to_region(cookies[:timezone])
      return region if region != "XX"
    end

    # Default to XX (Rest of World)
    "XX"
  end

  # Alias for views that expect @user_region
  def user_region
    @user_region ||= determine_user_region
  end
end
