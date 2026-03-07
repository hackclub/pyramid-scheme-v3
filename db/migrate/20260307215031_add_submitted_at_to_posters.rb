class AddSubmittedAtToPosters < ActiveRecord::Migration[8.1]
  def up
    add_column :posters, :submitted_at, :datetime, if_not_exists: true
    add_index :posters, :submitted_at, if_not_exists: true

    poster = Class.new(ActiveRecord::Base) do
      self.table_name = "posters"
    end

    poster.reset_column_information
    poster
      .where(submitted_at: nil, verification_status: %w[in_review on_hold success rejected])
      .update_all("submitted_at = COALESCE(verified_at, updated_at, created_at)")
  end

  def down
    remove_index :posters, :submitted_at, if_exists: true
    remove_column :posters, :submitted_at, if_exists: true
  end
end
