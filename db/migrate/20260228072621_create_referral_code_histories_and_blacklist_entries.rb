# frozen_string_literal: true

class CreateReferralCodeHistoriesAndBlacklistEntries < ActiveRecord::Migration[8.1]
  def change
    # Track all previous referral codes so they can't be stolen
    create_table :referral_code_histories do |t|
      t.references :user, null: false, foreign_key: true
      t.string :code, null: false
      t.string :code_type, null: false, default: "custom" # "custom" or "standard"
      t.datetime :expired_at
      t.timestamps
    end

    add_index :referral_code_histories, "LOWER(code)", name: "index_referral_code_histories_on_lower_code"
    add_index :referral_code_histories, [ :user_id, :code ], unique: true

    # Blacklist specific referral relationships
    create_table :referral_blacklist_entries do |t|
      t.string :block_type, null: false, default: "pair"
      # "pair" = block specific referrer→referred
      # "referrer" = block all referrals by this referrer
      # "referred" = block all referrals for this referred person

      t.string :referrer_identifier # slack_id, email, or user_id of the referrer
      t.string :referred_identifier # slack_id or email of the referred person
      t.text :reason
      t.references :created_by, foreign_key: { to_table: :users }, null: true
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :referral_blacklist_entries, :block_type
    add_index :referral_blacklist_entries, :referrer_identifier
    add_index :referral_blacklist_entries, :referred_identifier
    add_index :referral_blacklist_entries, :active
    add_index :referral_blacklist_entries, [ :referrer_identifier, :referred_identifier ],
              name: "idx_blacklist_pair", unique: true,
              where: "block_type = 'pair' AND active = true"
  end
end
