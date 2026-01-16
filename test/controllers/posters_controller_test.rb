# frozen_string_literal: true

require "test_helper"

class PostersControllerTest < ActionDispatch::IntegrationTest
  fixtures :all

  setup do
    @user = users(:regular_user)
    @admin = users(:admin)
    @flavortown = campaigns(:flavortown)
    @pending_poster = posters(:pending_poster)
    @verified_poster = posters(:verified_poster)

    # Stub external services
    stub_slack_notifications
  end

  # =============================================================================
  # AUTHENTICATION
  # =============================================================================
  test "create requires authentication" do
    post posters_path, params: {
      poster: { campaign_id: @flavortown.id, poster_type: "color" }
    }

    assert_redirected_to root_path
  end

  test "show requires authentication" do
    get poster_path(@pending_poster)

    assert_redirected_to root_path
  end

  # =============================================================================
  # CREATE
  # =============================================================================
  test "create poster with valid params" do
    sign_in_as(@user)

    assert_difference -> { Poster.count }, 1 do
      post posters_path, params: {
        poster: {
          campaign_id: @flavortown.id,
          poster_type: "color",
          country_code: "US"
        }
      }
    end

    poster = Poster.last
    assert_equal @user, poster.user
    assert_equal @flavortown, poster.campaign
    assert_equal "color", poster.poster_type
    assert_equal "pending", poster.verification_status
  end

  test "create poster generates unique tokens" do
    sign_in_as(@user)

    post posters_path, params: {
      poster: { campaign_id: @flavortown.id, poster_type: "color" }
    }

    poster = Poster.last
    assert_not_nil poster.qr_code_token
    assert_not_nil poster.referral_code
    assert_equal 12, poster.qr_code_token.length
    assert_equal 8, poster.referral_code.length
  end

  # =============================================================================
  # SHOW
  # =============================================================================
  test "show displays poster details" do
    sign_in_as(@user)

    get poster_path(@pending_poster)

    assert_response :success
  end

  # =============================================================================
  # DOWNLOAD
  # =============================================================================
  test "download generates PDF" do
    sign_in_as(@user)

    get download_poster_path(@pending_poster)

    assert_response :success
    assert_equal "application/pdf", response.content_type
  end

  # =============================================================================
  # MARK DIGITAL
  # =============================================================================
  test "mark_digital transitions pending poster to digital" do
    sign_in_as(@user)
    poster = create_poster(user: @user, campaign: @flavortown)

    post mark_digital_poster_path(poster)

    poster.reload
    assert_equal "digital", poster.verification_status
    assert_redirected_to campaign_path(@flavortown.slug)
  end

  test "mark_digital fails for non-pending poster" do
    sign_in_as(@user)
    # Need location_description to transition to in_review
    @pending_poster.update!(location_description: "Test location")
    @pending_poster.mark_in_review!

    post mark_digital_poster_path(@pending_poster)

    assert_response :redirect
    @pending_poster.reload
    assert_equal "in_review", @pending_poster.verification_status
  end

  # =============================================================================
  # HANDLE POSTER LINK
  # =============================================================================
  test "handle_poster_link with QR token redirects appropriately" do
    get poster_link_path(@pending_poster.qr_code_token)

    # Should handle the QR scan and redirect to referral URL
    assert_response :redirect
  end

  test "handle_poster_link with referral code redirects appropriately" do
    get poster_link_path(@pending_poster.referral_code)

    assert_response :redirect
  end

  test "handle_poster_link with invalid code redirects to root" do
    get poster_link_path("INVALID123")

    assert_response :redirect
    assert_redirected_to root_path
  end

  private

  # Sign in using session-based authentication for controller tests
  # Uses Mocha stubbing since integration tests can't directly set session
  def sign_in_as(user)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end
  def stub_slack_notifications
    SlackNotificationService.any_instance.stubs(:notify_poster_verified).returns(true)
    SlackNotificationService.any_instance.stubs(:notify_admin_new_poster).returns(true)
  end
end
