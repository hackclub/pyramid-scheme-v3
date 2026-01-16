# frozen_string_literal: true

class CreateVideoSubmissions < ActiveRecord::Migration[8.1]
  def change
    create_table :video_submissions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :campaign, null: false, foreign_key: true
      t.string :video_url
      t.string :status, default: "pending", null: false
      t.string :virality_status, default: "pending", null: false
      t.integer :shards_awarded, default: 0, null: false
      t.integer :viral_bonus, default: 0, null: false
      t.boolean :is_viral, default: false, null: false
      t.text :reviewer_notes
      t.datetime :reviewed_at
      t.references :reviewed_by, foreign_key: { to_table: :users }
      t.datetime :virality_checked_at
      t.references :virality_checked_by, foreign_key: { to_table: :users }
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :video_submissions, :status
    add_index :video_submissions, :virality_status
    add_index :video_submissions, [ :user_id, :created_at ]
    add_index :video_submissions, [ :campaign_id, :status ]
  end
end
