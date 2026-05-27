# frozen_string_literal: true

require "test_helper"

class PosterAutoVerificationServiceTest < ActiveSupport::TestCase
  setup do
    @poster = posters(:pending_poster)
    @service = PosterAutoVerificationService.new(@poster)
  end

  test "qr_matches_poster accepts the generated referral URL" do
    assert @service.send(:qr_matches_poster?, @poster.referral_url, @poster)
  end

  test "qr_matches_poster accepts equivalent URL with matching ref parameter" do
    assert @service.send(:qr_matches_poster?, "https://flavortown.hack.club?ref=#{@poster.referral_code}", @poster)
  end

  test "qr_matches_poster rejects arbitrary text containing the referral code" do
    assert_not @service.send(:qr_matches_poster?, "proof #{@poster.referral_code}", @poster)
  end

  test "qr_matches_poster rejects wrong campaign host with referral code" do
    assert_not @service.send(:qr_matches_poster?, "https://evil.example/?ref=#{@poster.referral_code}", @poster)
  end
end
