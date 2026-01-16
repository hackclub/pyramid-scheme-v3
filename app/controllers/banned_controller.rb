# frozen_string_literal: true

class BannedController < ApplicationController
  skip_before_action :authenticate_user!

  def show
    # If user is not banned, redirect them away
    unless current_user&.is_banned?
      redirect_to root_path
      return
    end

    @reason = current_user.banned_reason
    @contact_email = "parth.ahuja@outlook.in"

    render layout: false
  end
end
