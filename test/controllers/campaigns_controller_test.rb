# frozen_string_literal: true

require "test_helper"

class CampaignsControllerTest < ActionDispatch::IntegrationTest
  test "index renders sunset page without authentication" do
    get campaigns_path

    assert_response :success
    assert_includes response.body, "Pyramid Scheme has been sunset!"
    assert_includes response.body, "Please put in your orders before the website is shut down!"
  end

  test "show renders sunset page for existing campaign without authentication" do
    get campaign_path(campaigns(:flavortown).slug)

    assert_response :success
    assert_includes response.body, "Pyramid Scheme has been sunset!"
    assert_not_includes response.body, "This campaign is no longer available."
  end

  test "show renders sunset page for nonexistent campaign" do
    get campaign_path("nonexistent-campaign")

    assert_response :success
    assert_includes response.body, "Pyramid Scheme has been sunset!"
    assert_not_includes response.body, "This campaign is no longer available."
  end

  test "show renders sunset page for closed campaign without closed alert" do
    get campaign_path(campaigns(:closed_campaign).slug)

    assert_response :success
    assert_includes response.body, "Pyramid Scheme has been sunset!"
    assert_not_includes response.body, "This campaign is no longer available."
  end
end
