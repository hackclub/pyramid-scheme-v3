# frozen_string_literal: true

module Api
  module V1
    class WorkerController < ActionController::API
      before_action :authenticate_internal!

      # POST /api/v1/worker/jobs/airtable_sync
      # Trigger the Airtable sync job
      def trigger_airtable_sync
        # Check if a sync is already running (using advisory lock check)
        if AirtableSyncRun.where(status: "running").exists?
          return render json: {
            status: "already_running",
            message: "An Airtable sync is already in progress",
            current_run: AirtableSyncRun.where(status: "running").last&.as_json(only: [ :id, :started_at, :synced_count, :error_count ])
          }, status: :conflict
        end

        # Enqueue the job (or perform now based on param)
        if params[:sync] == "true" || params[:sync] == true
          AirtableSyncJob.perform_now
          last_run = AirtableSyncRun.order(created_at: :desc).first
          render json: {
            status: "completed",
            message: "Airtable sync completed",
            run: last_run&.as_json(only: [ :id, :started_at, :completed_at, :synced_count, :error_count, :status ])
          }
        else
          AirtableSyncJob.perform_later
          render json: {
            status: "enqueued",
            message: "Airtable sync job has been enqueued"
          }
        end
      end

      # POST /api/v1/worker/jobs/geocode
      # Trigger geocoding job for pending records
      def trigger_geocode
        limit = (params[:limit] || 100).to_i.clamp(1, 1000)

        pending_referral_logs = ReferralCodeLog.where(geocoding_status: nil).or(ReferralCodeLog.where(geocoding_status: "pending")).limit(limit)
        pending_login_logs = LoginLog.where(geocoding_status: nil).or(LoginLog.where(geocoding_status: "pending")).limit(limit)

        total_pending = pending_referral_logs.count + pending_login_logs.count

        if total_pending == 0
          return render json: {
            status: "no_pending",
            message: "No pending records to geocode"
          }
        end

        if params[:sync] == "true" || params[:sync] == true
          geocoded = 0
          errors = 0

          pending_referral_logs.find_each do |log|
            begin
              GeocodeIpJob.perform_now(log)
              geocoded += 1
            rescue => e
              errors += 1
              Rails.logger.error("Geocode error for ReferralCodeLog##{log.id}: #{e.message}")
            end
          end

          pending_login_logs.find_each do |log|
            begin
              GeocodeIpJob.perform_now(log)
              geocoded += 1
            rescue => e
              errors += 1
              Rails.logger.error("Geocode error for LoginLog##{log.id}: #{e.message}")
            end
          end

          render json: {
            status: "completed",
            message: "Geocoding completed",
            geocoded: geocoded,
            errors: errors
          }
        else
          # Enqueue jobs for each pending record
          enqueued = 0
          pending_referral_logs.find_each do |log|
            GeocodeIpJob.perform_later(log)
            enqueued += 1
          end
          pending_login_logs.find_each do |log|
            GeocodeIpJob.perform_later(log)
            enqueued += 1
          end

          render json: {
            status: "enqueued",
            message: "Geocoding jobs enqueued",
            enqueued: enqueued
          }
        end
      end

      # GET /api/v1/worker/status
      # Get worker status and job statistics
      def status
        render json: {
          status: "ok",
          timestamp: Time.current.iso8601,
          jobs: {
            airtable_sync: airtable_sync_stats,
            geocoding: geocoding_stats
          },
          queue: queue_stats
        }
      end

      # GET /api/v1/worker/jobs/airtable_sync/runs
      # Get recent Airtable sync runs
      def airtable_sync_runs
        limit = (params[:limit] || 10).to_i.clamp(1, 100)
        runs = AirtableSyncRun.order(created_at: :desc).limit(limit)

        render json: {
          runs: runs.map { |run|
            run.as_json(only: [ :id, :started_at, :completed_at, :synced_count, :error_count, :status ])
          }
        }
      end

      private

      def authenticate_internal!
        # Accept either X-Internal-Key header or Authorization Bearer token
        key = request.headers["X-Internal-Key"] ||
              request.headers["Authorization"]&.gsub(/^Bearer\s+/, "")

        unless key.present? && ActiveSupport::SecurityUtils.secure_compare(key, admin_key)
          render json: { error: "Unauthorized" }, status: :unauthorized
        end
      end

      def admin_key
        ENV["ADMIN_KEY"] || Rails.application.credentials.admin_key
      end

      def airtable_sync_stats
        last_run = AirtableSyncRun.order(created_at: :desc).first
        running = AirtableSyncRun.where(status: "running").exists?

        {
          last_run: last_run&.as_json(only: [ :id, :started_at, :completed_at, :synced_count, :error_count, :status ]),
          is_running: running,
          total_runs_today: AirtableSyncRun.where("created_at >= ?", Time.current.beginning_of_day).count,
          total_synced_today: AirtableSyncRun.where("created_at >= ?", Time.current.beginning_of_day).sum(:synced_count)
        }
      end

      def geocoding_stats
        {
          pending_referral_logs: ReferralCodeLog.where(geocoding_status: [ nil, "pending" ]).count,
          pending_login_logs: LoginLog.where(geocoding_status: [ nil, "pending" ]).count,
          geocoded_today: ReferralCodeLog.where(geocoding_status: "completed")
                            .where("updated_at >= ?", Time.current.beginning_of_day).count +
                          LoginLog.where(geocoding_status: "completed")
                            .where("updated_at >= ?", Time.current.beginning_of_day).count,
          failed_today: ReferralCodeLog.where(geocoding_status: "failed")
                          .where("updated_at >= ?", Time.current.beginning_of_day).count +
                        LoginLog.where(geocoding_status: "failed")
                          .where("updated_at >= ?", Time.current.beginning_of_day).count
        }
      end

      def queue_stats
        if defined?(SolidQueue)
          {
            ready: SolidQueue::ReadyExecution.count,
            scheduled: SolidQueue::ScheduledExecution.count,
            claimed: SolidQueue::ClaimedExecution.count,
            failed: SolidQueue::FailedExecution.count
          }
        else
          { message: "Queue stats not available" }
        end
      end
    end
  end
end
