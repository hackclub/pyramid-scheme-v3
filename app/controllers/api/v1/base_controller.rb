# frozen_string_literal: true

module Api
  module V1
    class BaseController < ActionController::API
      before_action :authenticate_api_key!

      attr_reader :current_api_key, :current_campaign

      private

      def authenticate_api_key!
        api_key = request.headers["Authorization"]&.gsub(/^Bearer\s+/, "")

        @current_api_key = ApiKey.authenticate(api_key)

        unless @current_api_key
          render json: { error: I18n.t("api.errors.invalid_api_key") }, status: :unauthorized
          return
        end

        @current_campaign = @current_api_key.campaign
      end

      def require_permission!(resource, action)
        return if current_api_key.has_permission?(resource, action)

        render json: {
          error: I18n.t("api.errors.permission_denied", action: action, resource: resource)
        }, status: :forbidden
      end

      def render_error(message, status: :unprocessable_entity)
        render json: { error: message }, status: status
      end

      def render_success(data, status: :ok)
        render json: data, status: status
      end
    end
  end
end
