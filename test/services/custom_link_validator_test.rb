# frozen_string_literal: true

require "test_helper"

class CustomLinkValidatorTest < ActiveSupport::TestCase
  setup do
    @user = users(:regular_user)
  end

  test "validate_format rejects non-letter characters" do
    validator = CustomLinkValidator.new(code: "abc123", user: @user)
    result = validator.validate_format

    assert_not result.valid?
    assert_includes result.errors.first, "only letters"
  end

  test "validate_format rejects codes over 64 characters" do
    long_code = "a" * 65
    validator = CustomLinkValidator.new(code: long_code, user: @user)
    result = validator.validate_format

    assert_not result.valid?
    assert_includes result.errors.first, "64 characters"
  end

  test "validate_format rejects codes under 3 characters" do
    validator = CustomLinkValidator.new(code: "ab", user: @user)
    result = validator.validate_format

    assert_not result.valid?
    assert_includes result.errors.first, "at least 3"
  end

  test "validate_format accepts valid codes" do
    validator = CustomLinkValidator.new(code: "MyCustomLink", user: @user)
    result = validator.validate_format

    assert result.valid?
    assert_empty result.errors
  end

  test "validate_full checks uniqueness" do
    # Stub external service
    stub_request(:get, "https://ysws.hackclub.com/feed.xml")
      .to_return(status: 200, body: "", headers: {})

    # Create another user with the custom code
    other_user = users(:admin)
    other_user.update!(custom_referral_code: "TakenCode")

    validator = CustomLinkValidator.new(code: "TakenCode", user: @user)
    result = validator.validate_full

    assert_not result.valid?
    assert_includes result.errors.first, "Already taken"
  end
end
