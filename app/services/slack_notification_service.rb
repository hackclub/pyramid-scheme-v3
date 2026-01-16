# frozen_string_literal: true

# Sends Slack notifications to users and admins.
#
# Handles direct messages for user notifications (poster verification,
# referral completion) and admin alerts for new submissions.
#
# @example Send a poster verification notification
#   service = SlackNotificationService.new
#   service.notify_poster_verified(
#     user: user,
#     poster: poster,
#     shards: 10
#   )
#
# @note Requires SLACK_BOT_TOKEN environment variable to be set.
#   The bot must have `chat:write` and `im:write` scopes.
class SlackNotificationService
  class NotificationError < StandardError; end

  def initialize
    @bot_token = ENV["SLACK_BOT_TOKEN"]
  end

  # Send a DM to a user by their Slack ID
  # @param slack_id [String] The Slack user ID
  # @param message [String] The message to send (supports Slack markdown)
  # @param blocks [Array, nil] Optional blocks for rich formatting
  # @return [Boolean] Whether the message was sent successfully
  def send_dm(slack_id:, message:, blocks: nil)
    return false unless @bot_token.present? && slack_id.present?

    begin
      # Open a DM channel with the user
      conversation_response = connection.post("https://slack.com/api/conversations.open") do |req|
        req.headers["Authorization"] = "Bearer #{@bot_token}"
        req.headers["Content-Type"] = "application/json"
        req.body = { users: slack_id }.to_json
      end

      conversation_result = JSON.parse(conversation_response.body)
      return false unless conversation_result["ok"]

      channel_id = conversation_result["channel"]["id"]

      # Send the message
      message_body = {
        channel: channel_id,
        text: message
      }
      message_body[:blocks] = blocks if blocks.present?

      message_response = connection.post("https://slack.com/api/chat.postMessage") do |req|
        req.headers["Authorization"] = "Bearer #{@bot_token}"
        req.headers["Content-Type"] = "application/json"
        req.body = message_body.to_json
      end

      message_result = JSON.parse(message_response.body)
      message_result["ok"]
    rescue => e
      Rails.logger.error("SlackNotificationService error: #{e.message}")
      false
    end
  end

  # Send a notification about poster verification success
  # @param user [User] The user who earned shards
  # @param poster [Poster] The verified poster
  # @param shards [Integer] Number of shards awarded
  def notify_poster_verified(user:, poster:, shards:)
    return unless user.slack_id.present?

    message = "🎉 *Your poster has been verified!*\n\n" \
              "You've earned *#{shards} shard#{shards == 1 ? '' : 's'}* for your poster" \
              "#{poster.location_description.present? ? " at #{poster.location_description}" : ''}.\n\n" \
              "Keep spreading the word about Flavortown! 🍕"

    send_dm(slack_id: user.slack_id, message: message)
  end

  # Send a notification about referral completion
  # @param user [User] The user who earned shards (referrer)
  # @param referral [Referral] The completed referral
  # @param shards [Integer] Number of shards awarded
  def notify_referral_completed(user:, referral:, shards:)
    return unless user.slack_id.present?

    message = "🎉 *Referral completed!*\n\n" \
              "Your referral for *#{referral.referred_identifier}* has completed all requirements!\n" \
              "You've earned *#{shards} shard#{shards == 1 ? '' : 's'}*.\n\n" \
              "Keep inviting friends to Flavortown! 🍕"

    send_dm(slack_id: user.slack_id, message: message)
  end

  # Send admin notification for new poster submission
  # @param poster [Poster] The submitted poster
  def notify_admin_new_poster(poster:)
    admin_slack_id = ENV["ADMIN_NOTIFICATION_SLACK_ID"]
    return unless admin_slack_id.present?

    user = poster.user
    status_emoji = case poster.verification_status
    when "success" then "✅"
    when "pending" then "⏳"
    when "in_review" then "👀"
    else "📋"
    end

    message = "#{status_emoji} *New Poster Submission*\n\n" \
              "*User:* #{user&.display_name || 'Unknown'} (#{user&.slack_id || 'No Slack ID'})\n" \
              "*Location:* #{poster.location_description || 'Not specified'}\n" \
              "*Type:* #{poster.poster_type}\n" \
              "*Status:* #{poster.verification_status}\n" \
              "*Poster ID:* #{poster.id}"

    send_dm(slack_id: admin_slack_id, message: message)
  end

  # Send admin notification for new referral
  # @param referral [Referral] The new referral
  def notify_admin_new_referral(referral:)
    admin_slack_id = ENV["ADMIN_NOTIFICATION_SLACK_ID"]
    return unless admin_slack_id.present?

    referrer = referral.referrer
    status_emoji = case referral.status
    when "completed" then "✅"
    when "id_verified" then "🆔"
    else "⏳"
    end

    message = "#{status_emoji} *New Referral*\n\n" \
              "*Referrer:* #{referrer&.display_name || 'Unknown'} (#{referrer&.slack_id || 'No Slack ID'})\n" \
              "*Referred:* #{referral.referred_identifier}\n" \
              "*Type:* #{referral.referral_type}\n" \
              "*Status:* #{referral.status}\n" \
              "*Campaign:* #{referral.campaign&.name || 'Unknown'}"

    send_dm(slack_id: admin_slack_id, message: message)
  end

  private

  def connection
    @connection ||= Faraday.new do |f|
      f.adapter Faraday.default_adapter
    end
  end
end
