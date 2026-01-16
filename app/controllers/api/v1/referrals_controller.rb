# frozen_string_literal: true

module Api
  module V1
    class ReferralsController < BaseController
      before_action :require_permission!, only: [ :create, :update, :batch_sync ]

      # GET /api/v1/referrals
      def index
        referrals = current_campaign.referrals

        if params[:referrer_id].present?
          referrer = User.find_by(slack_id: params[:referrer_id])
          referrals = referrals.where(referrer: referrer) if referrer
        end

        if params[:status].present?
          referrals = referrals.where(status: params[:status])
        end

        render_success({
          referrals: referrals.map { |r| serialize_referral(r) },
          total: referrals.count
        })
      end

      # GET /api/v1/referrals_valid
      def referrals_valid
        # Get all user referral codes (both default and custom) for campaign participants
        user_codes = current_campaign.participants.pluck(:referral_code, :custom_referral_code).flatten.compact

        # Get all poster referral codes for the campaign
        poster_codes = current_campaign.posters.pluck(:referral_code).compact

        # Combine and deduplicate
        all_codes = (user_codes + poster_codes).uniq

        render_success({
          referral_codes: all_codes
        })
      end

      # GET /api/v1/referrals/:id
      def show
        referral = current_campaign.referrals.find_by(id: params[:id])

        unless referral
          return render_error("Referral not found", status: :not_found)
        end

        render_success(referral: serialize_referral(referral))
      end

      # POST /api/v1/referrals
      def create
        require_permission!(:referrals, :write)

        referrer = User.find_by(slack_id: params[:referrer_slack_id])

        unless referrer
          return render_error("Referrer not found")
        end

        referral = current_campaign.referrals.new(
          referrer: referrer,
          referred_identifier: params[:referred_identifier],
          external_program: params[:external_program],
          metadata: params[:metadata] || {}
        )

        if referral.save
          render_success({ referral: serialize_referral(referral) }, status: :created)
        else
          render_error(referral.errors.full_messages.join(", "))
        end
      end

      # PATCH /api/v1/referrals/:id
      def update
        require_permission!(:referrals, :write)

        referral = current_campaign.referrals.find_by(id: params[:id])

        unless referral
          return render_error("Referral not found", status: :not_found)
        end

        # Handle status transitions
        case params[:status]
        when "id_verified"
          referral.verify_identity!
        when "completed"
          if params[:tracked_minutes].present?
            referral.update_tracked_time!(params[:tracked_minutes].to_i)
          end
          referral.complete! if referral.id_verified?
        end

        # Update tracked time
        if params[:tracked_minutes].present? && params[:status].blank?
          referral.update_tracked_time!(params[:tracked_minutes].to_i)
        end

        # Update metadata
        if params[:metadata].present?
          referral.update!(metadata: referral.metadata.merge(params[:metadata].to_unsafe_h))
        end

        render_success(referral: serialize_referral(referral.reload))
      rescue ActiveRecord::RecordInvalid => e
        render_error(e.message)
      end

      # POST /api/v1/referrals/batch_sync
      def batch_sync
        require_permission!(:referrals, :write)

        results = { created: [], updated: [], errors: [] }

        params[:referrals].each do |ref_params|
          referrer = User.find_by(slack_id: ref_params[:referrer_slack_id])

          unless referrer
            results[:errors] << { referred_identifier: ref_params[:referred_identifier], error: "Referrer not found" }
            next
          end

          referral = current_campaign.referrals.find_by(
            referrer: referrer,
            referred_identifier: ref_params[:referred_identifier]
          )

          if referral
            # Update existing
            process_referral_update(referral, ref_params)
            results[:updated] << serialize_referral(referral.reload)
          else
            # Create new
            referral = current_campaign.referrals.new(
              referrer: referrer,
              referred_identifier: ref_params[:referred_identifier],
              external_program: ref_params[:external_program],
              metadata: ref_params[:metadata] || {}
            )

            if referral.save
              process_referral_update(referral, ref_params) if ref_params[:status] || ref_params[:tracked_minutes]
              results[:created] << serialize_referral(referral.reload)
            else
              results[:errors] << { referred_identifier: ref_params[:referred_identifier], error: referral.errors.full_messages.join(", ") }
            end
          end
        end

        render_success(results)
      end

      private

      def require_permission!(resource = nil, action = nil)
        return super(resource, action) if resource && action

        # Default permission check for the action
        super(:referrals, action_name == "index" || action_name == "show" ? :read : :write)
      end

      def process_referral_update(referral, ref_params)
        case ref_params[:status]
        when "id_verified"
          referral.verify_identity!
        when "completed"
          referral.update_tracked_time!(ref_params[:tracked_minutes].to_i) if ref_params[:tracked_minutes].present?
          referral.complete! if referral.id_verified?
        end

        if ref_params[:tracked_minutes].present? && ref_params[:status].blank?
          referral.update_tracked_time!(ref_params[:tracked_minutes].to_i)
        end

        if ref_params[:metadata].present?
          referral.update!(metadata: referral.metadata.merge(ref_params[:metadata].to_h))
        end
      end

      def serialize_referral(referral)
        {
          id: referral.id,
          referrer_slack_id: referral.referrer.slack_id,
          referred_identifier: referral.referred_identifier,
          status: referral.status,
          tracked_minutes: referral.tracked_minutes,
          progress_percentage: referral.progress_percentage,
          external_program: referral.external_program,
          metadata: referral.metadata,
          verified_at: referral.verified_at,
          completed_at: referral.completed_at,
          created_at: referral.created_at,
          updated_at: referral.updated_at
        }
      end
    end
  end
end
