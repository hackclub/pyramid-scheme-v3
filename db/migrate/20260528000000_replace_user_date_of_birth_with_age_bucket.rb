# frozen_string_literal: true

class ReplaceUserDateOfBirthWithAgeBucket < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :age_bucket, :string, if_not_exists: true

    cutoff = connection.quote(18.years.ago.to_date)
    execute <<~SQL.squish
      UPDATE users
      SET age_bucket = CASE WHEN date_of_birth <= #{cutoff} THEN 'adult' ELSE 'minor' END
      WHERE date_of_birth IS NOT NULL
    SQL

    remove_column :users, :date_of_birth, if_exists: true
    add_index :users, :age_bucket, if_not_exists: true
  end

  def down
    add_column :users, :date_of_birth, :date, if_not_exists: true
    remove_index :users, :age_bucket, if_exists: true
    remove_column :users, :age_bucket, if_exists: true
  end
end
