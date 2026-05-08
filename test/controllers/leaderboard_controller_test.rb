# frozen_string_literal: true

require "test_helper"

class LeaderboardControllerTest < ActionDispatch::IntegrationTest
  test "public leaderboard redirects to root" do
    get leaderboard_path

    assert_redirected_to root_path
    assert_equal 303, response.status
  end
end
