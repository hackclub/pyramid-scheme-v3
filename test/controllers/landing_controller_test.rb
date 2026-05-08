# frozen_string_literal: true

require "test_helper"

class LandingControllerTest < ActionDispatch::IntegrationTest
  test "index renders sunset page when no campaign exists" do
    LandingController.any_instance.stubs(:landing_campaign).returns(nil)

    get root_path

    assert_response :success
    assert_includes response.body, "Pyramid Scheme has been sunset!"
  end
end
