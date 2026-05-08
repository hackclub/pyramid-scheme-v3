# frozen_string_literal: true

class LeaderboardController < ApplicationController
  skip_before_action :authenticate_user!, only: :index

  def index
    redirect_to root_path, status: :see_other
  end
end
