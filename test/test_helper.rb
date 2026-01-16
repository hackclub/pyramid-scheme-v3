# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"
require "mocha/minitest"

# Disable external HTTP requests in tests (except localhost)
WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...

    # Helper to sign in a user for controller tests
    def sign_in(user)
      session[:user_id] = user.id
    end

    # Helper to sign out
    def sign_out
      session.delete(:user_id)
    end

    # Helper to create a valid user
    def create_user(attrs = {})
      User.create!({
        email: "test-#{SecureRandom.hex(4)}@example.com",
        display_name: "Test User",
        role: :user,
        slack_id: "U#{SecureRandom.hex(6).upcase}"
      }.merge(attrs))
    end

    # Helper to create a campaign
    def create_campaign(attrs = {})
      Campaign.create!({
        name: "Test Campaign",
        slug: "test-#{SecureRandom.hex(4)}",
        theme: "flavortown",
        status: "open",
        active: true,
        referral_shards: 3,
        poster_shards: 1,
        required_coding_minutes: 60
      }.merge(attrs))
    end

    # Helper to create a poster
    def create_poster(user:, campaign:, **attrs)
      Poster.create!({
        user: user,
        campaign: campaign,
        poster_type: "color",
        verification_status: "pending",
        qr_code_token: SecureRandom.alphanumeric(12),
        referral_code: SecureRandom.alphanumeric(8).upcase
      }.merge(attrs))
    end

    # Helper to create a referral
    def create_referral(referrer:, campaign:, **attrs)
      Referral.create!({
        referrer: referrer,
        campaign: campaign,
        referred_identifier: "referred-#{SecureRandom.hex(4)}@example.com",
        referral_type: "link",
        status: :pending,
        tracked_minutes: 0
      }.merge(attrs))
    end

    # Helper to stub Slack notifications
    def stub_slack_notifications
      SlackNotificationService.any_instance.stubs(:notify_poster_verified).returns(true)
      SlackNotificationService.any_instance.stubs(:notify_admin_new_poster).returns(true)
    end
  end
end

module ActionDispatch
  class IntegrationTest
    # Helper to sign in a user for integration tests
    def sign_in_as(user)
      post auth_callback_path, params: {}, headers: {}, env: { "rack.session" => { user_id: user.id } }
    end
  end
end
