# frozen_string_literal: true

# Service to fetch static Pyramid V2 statistics
# Pyramid V2 is dormant/shut down, so this data never changes
# NOTE: These queries access an external database that may not exist.
# Errors are expected and logged, returning safe defaults.
class PyramidV2StatsService
  class << self
    # Get all V2 stats (cached forever since V2 is dormant)
    def stats
      Rails.cache.fetch("pyramid_v2_stats", expires_in: 1.year) do
        fetch_stats
      end
    end

    # Force refresh the cache (only needed if data needs correction)
    def refresh!
      Rails.cache.delete("pyramid_v2_stats")
      stats
    end

    private

    def fetch_stats
      {
        total_users: count_unique_referrers,
        total_referrals: count_referrals,
        total_completed_referrals: count_completed_referrals,
        total_posters: count_posters,
        total_approved_posters: count_approved_posters,
        start_date: earliest_date,
        end_date: latest_date
      }
    rescue StandardError => e
      Rails.logger.error "[PyramidV2Stats] Error fetching stats: #{e.message}"
      default_stats
    end

    def count_unique_referrers
      PyramidV2::ReferredSignUp.distinct.count(:referrer_id)
    rescue ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished => e
      Rails.logger.warn "[PyramidV2Stats] DB unavailable for count_unique_referrers: #{e.message}"
      0
    end

    def count_referrals
      PyramidV2::ReferredSignUp.count
    rescue ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished => e
      Rails.logger.warn "[PyramidV2Stats] DB unavailable for count_referrals: #{e.message}"
      0
    end

    def count_completed_referrals
      PyramidV2::ReferredSignUp.where.not(qualified_detected_at: nil).count
    rescue ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished => e
      Rails.logger.warn "[PyramidV2Stats] DB unavailable for count_completed_referrals: #{e.message}"
      0
    end

    def count_posters
      PyramidV2::Poster.count
    rescue ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished => e
      Rails.logger.warn "[PyramidV2Stats] DB unavailable for count_posters: #{e.message}"
      0
    end

    def count_approved_posters
      PyramidV2::Poster.where(status: "approved").count
    rescue ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished => e
      Rails.logger.warn "[PyramidV2Stats] DB unavailable for count_approved_posters: #{e.message}"
      0
    end

    def earliest_date
      [
        PyramidV2::ReferredSignUp.minimum(:created_at),
        PyramidV2::Poster.minimum(:created_at)
      ].compact.min&.to_date
    rescue ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished => e
      Rails.logger.warn "[PyramidV2Stats] DB unavailable for earliest_date: #{e.message}"
      nil
    end

    def latest_date
      [
        PyramidV2::ReferredSignUp.maximum(:created_at),
        PyramidV2::Poster.maximum(:created_at)
      ].compact.max&.to_date
    rescue ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished => e
      Rails.logger.warn "[PyramidV2Stats] DB unavailable for latest_date: #{e.message}"
      {
        total_users: 0,
        total_referrals: 0,
        total_completed_referrals: 0,
        total_posters: 0,
        total_approved_posters: 0,
        start_date: nil,
        end_date: nil
      }
    end
  end
end
