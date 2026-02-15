# frozen_string_literal: true

require "test_helper"

module Admin
  class PostersControllerTest < ActionDispatch::IntegrationTest
    fixtures :all

    setup do
      @admin = users(:admin)
    end

    test "index supports all status filter" do
      sign_in_as_admin

      assert_nothing_raised do
        get admin_posters_path, params: { status: "all" }
      end

      assert_response :success
    end

    private

    def sign_in_as_admin
      ApplicationController.any_instance.stubs(:current_user).returns(@admin)
      ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
    end
  end
end
