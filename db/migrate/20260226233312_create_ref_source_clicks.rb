class CreateRefSourceClicks < ActiveRecord::Migration[8.1]
  def change
    create_table :ref_source_clicks do |t|
      t.string :ref_source, null: false
      t.string :ip_address
      t.string :user_agent
      t.string :path

      t.timestamps
    end

    add_index :ref_source_clicks, :ref_source
    add_index :ref_source_clicks, :created_at
  end
end
