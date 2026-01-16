# frozen_string_literal: true

# Performance migration: Add composite indexes for common query patterns
# and counter cache for poster scans to prevent N+1 queries
class AddPerformanceIndexes < ActiveRecord::Migration[8.1]
  def change
    # Counter cache for poster scans count (prevents N+1 in poster listings)
    add_column :posters, :poster_scans_count, :integer, default: 0, null: false

    # Composite index for poster queries by user, campaign, and status
    # Covers: user's posters for a campaign, filtered by verification status
    add_index :posters, [ :user_id, :campaign_id, :verification_status ],
              name: "idx_posters_user_campaign_status"

    # Composite index for referral queries
    # Covers: campaign referrals by status and type
    add_index :referrals, [ :campaign_id, :status, :referral_type ],
              name: "idx_referrals_campaign_status_type"

    # Backfill counter cache values
    reversible do |dir|
      dir.up do
        execute <<-SQL.squish
          UPDATE posters
          SET poster_scans_count = (
            SELECT COUNT(*) FROM poster_scans
            WHERE poster_scans.poster_id = posters.id
          )
        SQL
      end
    end
  end
end
