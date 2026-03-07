class AddSubmittedAtToPosters < ActiveRecord::Migration[8.1]
  def up
    add_column :posters, :submitted_at, :datetime
    add_index :posters, :submitted_at

    execute <<~SQL.squish
      UPDATE posters
         SET submitted_at = COALESCE(verified_at, updated_at, created_at)
       WHERE submitted_at IS NULL
         AND verification_status IN ('in_review', 'on_hold', 'success', 'rejected')
    SQL
  end

  def down
    remove_index :posters, :submitted_at
    remove_column :posters, :submitted_at
  end
end
