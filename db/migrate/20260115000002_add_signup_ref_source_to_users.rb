class AddSignupRefSourceToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :signup_ref_source, :string, limit: 64
    add_index :users, :signup_ref_source
  end
end
