# frozen_string_literal: true

class LandingController < ApplicationController
  skip_before_action :authenticate_user!
  layout "landing"

  # Pyramid Scheme V3 has ended — the landing page is now a static notice.
  def index
  end
end
