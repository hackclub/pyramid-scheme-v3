class AddDateOfBirthToUsersAndBannerToCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :date_of_birth, :date
    add_column :campaigns, :banner_text, :text
    add_column :campaigns, :banner_type, :string, default: "info"
  end
end
