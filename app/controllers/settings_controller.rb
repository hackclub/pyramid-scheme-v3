# frozen_string_literal: true

class SettingsController < ApplicationController
  def index
    @user = current_user
  end

  def update
    @user = current_user

    if @user.update(settings_params)
      redirect_to settings_path, notice: t("flash.settings_saved")
    else
      render :index, status: :unprocessable_entity
    end
  end

  private

  def settings_params
    params.require(:user).permit(:leaderboard_opted_out, :display_name)
  end
end
