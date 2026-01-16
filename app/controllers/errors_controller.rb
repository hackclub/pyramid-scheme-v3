# frozen_string_literal: true

class ErrorsController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :verify_authenticity_token
  layout false

  def not_found
    render_error(
      status: :not_found,
      title: "Oops",
      message: "We couldn't find that page. It might have moved or never existed."
    )
  end

  def unprocessable_entity
    render_error(
      status: :unprocessable_entity,
      title: "We can't process that",
      message: "Something about this request doesn't look right. Give it another try."
    )
  end

  def internal_server_error
    render_error(
      status: :internal_server_error,
      title: "We hit a snag",
      message: "Our servers stumbled. We're logging this so we can fix it."
    )
  end

  private

  def render_error(status:, title:, message:)
    signed_in = safe_signed_in?
    @status_code = Rack::Utils::SYMBOL_TO_STATUS_CODE[status]
    @title = title
    @message = message
    @signed_in = signed_in
    @cta_path = signed_in ? dashboard_path : root_path
    @cta_label = signed_in ? "Back to dashboard" : "Return home"
    @secondary_cta = signed_in ? shop_path : auth_path
    @secondary_label = signed_in ? "Open shop" : "Sign in"

    render :show, status: status
  end

  def safe_signed_in?
    user_signed_in?
  rescue StandardError
    false
  end
end
