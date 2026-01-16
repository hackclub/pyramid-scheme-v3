require "lucide-rails"

# General application-wide view helpers.
#
# Provides utility methods for common view operations like status badges,
# email censoring, country name formatting, and permission checks.
module ApplicationHelper
  include LucideRails::RailsHelper
  include IconHelper

  # Returns CSS classes for a poster verification status badge.
  #
  # @param status [String, Symbol] The poster verification status
  # @return [String] Tailwind CSS classes for the badge
  def poster_status_badge_class(status)
    case status.to_s
    when "success" then "bg-green-500/10 text-green-600"
    when "digital" then "bg-purple-500/10 text-purple-600"
    when "rejected" then "bg-destructive/10 text-destructive"
    when "on_hold" then "bg-amber-500/10 text-amber-600"
    when "pending" then "bg-blue-500/10 text-blue-600"
    when "in_review" then "bg-yellow-500/10 text-yellow-700"
    else "bg-gray-500/10 text-gray-700"
    end
  end

  # Returns CSS classes for a shop order status badge.
  #
  # @param status [String, Symbol] The order status
  # @return [String] Tailwind CSS classes for the badge
  def order_status_badge_class(status)
    case status.to_s
    when "fulfilled" then "bg-green-500/10 text-green-600"
    when "cancelled" then "bg-destructive/10 text-destructive"
    when "approved" then "bg-blue-500/10 text-blue-600"
    when "in_review" then "bg-indigo-500/10 text-indigo-600"
    when "on_hold" then "bg-orange-500/10 text-orange-600"
    else "bg-amber-500/10 text-amber-700"
    end
  end

  # Returns CSS classes for a referral status badge.
  #
  # @param referral [Referral] The referral record
  # @return [String] Tailwind CSS classes for the badge
  def referral_status_badge_class(referral)
    if referral.completed?
      "bg-green-500/10 text-green-500"
    elsif referral.id_verified?
      "bg-yellow-500/10 text-yellow-500"
    elsif referral.pending_status&.downcase == "rejected"
      "bg-red-500/10 text-red-500"
    else
      "bg-blue-500/10 text-blue-500"
    end
  end

  # Returns the human-readable label for a referral status.
  #
  # @param referral [Referral] The referral record
  # @return [String] The display label for the status
  def referral_status_label(referral)
    referral.pending? ? referral.pending_status_label : referral.status.humanize
  end

  # Returns the label and CSS classes for a full-color poster status badge.
  #
  # @param status [String, Symbol] The poster verification status
  # @return [Array<String, String>] Tuple of [label, css_classes]
  def poster_status_badge_full(status)
    case status.to_s
    when "pending" then [ "Pending: Submit Proof", "bg-yellow-500 text-white" ]
    when "in_review" then [ "In Review", "bg-blue-600 text-white" ]
    when "success" then [ "Approved", "bg-green-600 text-white" ]
    when "digital" then [ "Digital", "bg-purple-600 text-white" ]
    when "on_hold" then [ "On Hold", "bg-orange-500 text-white" ]
    when "rejected" then [ "Rejected", "bg-red-600 text-white" ]
    else [ status.to_s.humanize, "bg-gray-600 text-white" ]
    end
  end

  # Censors an email address for display by masking part of the local portion.
  #
  # @param email [String, nil] The email address to censor
  # @return [String] The censored email or "—" if blank
  # @example
  #   censor_email("john.doe@example.com") # => "jo***@example.com"
  #   censor_email(nil) # => "—"
  #
  # @note A similar method exists in AirtableReferralImporter#censor_email
  #   with slightly different masking logic. Consider consolidating.
  def censor_email(email)
    return "—" if email.blank?

    value = email.to_s
    return value if !value.include?("@")

    local, domain = value.split("@", 2)
    local = local.to_s
    domain = domain.to_s

    masked_local = if local.length <= 1
      "*"
    elsif local.length == 2
      "#{local[0]}*"
    else
      "#{local[0, 2]}#{'*' * [ local.length - 2, 3 ].min}"
    end

    "#{masked_local}@#{domain}"
  end

  # Get the application base URL - uses request if available, falls back to ENV
  def app_base_url
    if defined?(request) && request.present?
      request.base_url
    else
      Rails.application.config.x.app_host
    end
  end

  # Returns a human-friendly country name for a given country code.
  def country_name_from_code(code)
    country = ISO3166::Country[code]
    return code if country.nil?

    country.translations[I18n.locale.to_s] ||
      country.common_name ||
      country.iso_short_name ||
      country.name ||
      code
  end

  # Converts a country code to its flag emoji
  def country_code_to_flag(code)
    return "" if code.blank?

    code.upcase.chars.map { |char| (char.ord + 127397).chr("UTF-8") }.join
  end

  # Returns all countries with a readable name for select inputs.
  def country_options_for_select
    ISO3166::Country.all
      .map { |country|
        [
          country.translations[I18n.locale.to_s] ||
            country.common_name ||
            country.iso_short_name ||
            country.name,
          country.alpha2
        ]
      }
      .reject { |name, code| name.blank? || code.blank? }
      .sort_by { |name, _code| name }
  end

  # Check if current user can impersonate other users
  def can_impersonate_users?
    return false unless current_user&.admin?

    # Allow the primary admin (from env) to impersonate
    admin_slack_id = ENV["ADMIN_NOTIFICATION_SLACK_ID"]
    return true if admin_slack_id.present? && current_user.slack_id == admin_slack_id

    # Also allow based on a list of allowed Slack IDs
    allowed_impersonators = ENV.fetch("ALLOWED_IMPERSONATORS", "").split(",").map(&:strip)
    allowed_impersonators.include?(current_user.slack_id)
  end
end
