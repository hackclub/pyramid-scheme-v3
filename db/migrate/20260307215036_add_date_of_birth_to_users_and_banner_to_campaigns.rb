class AddDateOfBirthToUsersAndBannerToCampaigns < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :date_of_birth, :date, if_not_exists: true
    add_column :campaigns, :banner_text, :text, if_not_exists: true
    add_column :campaigns, :banner_type, :string, default: "info", if_not_exists: true
  end

  def down
    remove_column :users, :date_of_birth, if_exists: true
    remove_column :campaigns, :banner_text, if_exists: true
    remove_column :campaigns, :banner_type, if_exists: true
  end
end
