# frozen_string_literal: true

require "test_helper"

class LandingControllerTest < ActionDispatch::IntegrationTest
  test "index renders the ended notice" do
    get root_path

    assert_response :success
    assert_includes response.body, "Pyramid Scheme V3 has ended!"
  end

  test "public pages are closed and redirect to the ended screen" do
    get leaderboard_path

    assert_redirected_to root_path
  end

  test "data api is closed with 410 gone" do
    get "/api/v1/codes/lookup"

    assert_response :gone
  end
end
