# frozen_string_literal: true

class ScopeReferralUniquenessToCampaign < ActiveRecord::Migration[8.1]
  OLD_INDEX_NAME = "index_referrals_on_referrer_id_and_referred_identifier"
  NEW_INDEX_NAME = "index_referrals_on_referrer_referred_campaign"

  def up
    remove_index :referrals, name: OLD_INDEX_NAME, if_exists: true

    add_index :referrals, [ :referrer_id, :referred_identifier, :campaign_id ],
              unique: true,
              name: NEW_INDEX_NAME,
              if_not_exists: true
  end

  def down
    remove_index :referrals, name: NEW_INDEX_NAME, if_exists: true

    add_index :referrals, [ :referrer_id, :referred_identifier ],
              unique: true,
              name: OLD_INDEX_NAME,
              if_not_exists: true
  end
end
