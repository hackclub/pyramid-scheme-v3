# frozen_string_literal: true

# Initial schema migration for Pyramid.
# This migration is idempotent - safe to run on existing databases.
# It creates all tables with if_not_exists: true and skips existing indexes.
class InitialSchema < ActiveRecord::Migration[8.1]
  def change
    # Enable extensions
    enable_extension "pg_catalog.plpgsql"

    # Active Storage tables
    create_table :active_storage_blobs, if_not_exists: true do |t|
      t.string :key, null: false
      t.string :filename, null: false
      t.string :content_type
      t.text :metadata
      t.string :service_name, null: false
      t.bigint :byte_size, null: false
      t.string :checksum
      t.datetime :created_at, null: false
    end
    add_index_if_missing :active_storage_blobs, :key, unique: true

    create_table :active_storage_attachments, if_not_exists: true do |t|
      t.string :name, null: false
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.bigint :blob_id, null: false
      t.datetime :created_at, null: false
    end
    add_index_if_missing :active_storage_attachments, :blob_id
    add_index_if_missing :active_storage_attachments, [ :record_type, :record_id, :name, :blob_id ],
                         name: "index_active_storage_attachments_uniqueness", unique: true
    add_fk_if_missing :active_storage_attachments, :active_storage_blobs, column: :blob_id

    create_table :active_storage_variant_records, if_not_exists: true do |t|
      t.bigint :blob_id, null: false
      t.string :variation_digest, null: false
    end
    add_index_if_missing :active_storage_variant_records, [ :blob_id, :variation_digest ],
                         name: "index_active_storage_variant_records_uniqueness", unique: true
    add_fk_if_missing :active_storage_variant_records, :active_storage_blobs, column: :blob_id

    # Users
    create_table :users, if_not_exists: true do |t|
      t.string :email, null: false
      t.string :display_name, null: false
      t.string :first_name
      t.string :last_name
      t.string :avatar
      t.string :slack_id
      t.string :referral_code
      t.string :custom_referral_code
      t.datetime :custom_referral_code_changed_at
      t.integer :role, default: 0, null: false
      t.integer :total_shards, default: 0, null: false
      t.integer :referral_count, default: 0, null: false
      t.integer :poster_count, default: 0, null: false
      t.integer :bonus_paid_posters, default: 0, null: false
      t.boolean :leaderboard_opted_out, default: false, null: false
      t.boolean :is_banned, default: false, null: false
      t.datetime :banned_at
      t.text :banned_reason
      t.text :internal_ban_reason
      t.text :internal_notes
      t.string :last_ip_address
      t.datetime :last_seen_at
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.string :city
      t.string :region
      t.string :country_code
      t.string :country_name
      t.string :postal_code
      t.string :org
      t.string :timezone
      t.datetime :geocoded_at
      t.timestamps
    end
    add_index_if_missing :users, :email, unique: true
    add_index_if_missing :users, :slack_id, unique: true
    add_index_if_missing :users, :referral_code, unique: true
    add_index_if_missing :users, :custom_referral_code, unique: true
    add_index_if_missing :users, :role
    add_index_if_missing :users, :total_shards
    add_index_if_missing :users, :referral_count
    add_index_if_missing :users, :poster_count
    add_index_if_missing :users, :leaderboard_opted_out
    add_index_if_missing :users, :banned_at
    add_index_if_missing :users, :last_seen_at
    add_index_if_missing :users, :latitude
    add_index_if_missing :users, :longitude
    add_index_if_missing :users, :geocoded_at

    # Campaigns
    create_table :campaigns, if_not_exists: true do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :theme, null: false
      t.jsonb :theme_config, default: {}
      t.string :subdomain
      t.string :base_url
      t.text :custom_css
      t.datetime :starts_at
      t.datetime :ends_at
      t.boolean :active, default: true, null: false
      t.string :status, default: "open", null: false
      t.integer :referral_shards, default: 3, null: false
      t.integer :poster_shards, default: 1, null: false
      t.integer :required_coding_minutes, default: 60, null: false
      t.jsonb :poster_templates, default: {}, null: false
      t.jsonb :poster_qr_coordinates, default: {}, null: false
      t.jsonb :i18n_overrides, default: {}, null: false
      t.string :airtable_base_id
      t.string :airtable_table_id
      t.boolean :airtable_sync_enabled, default: false, null: false
      t.jsonb :airtable_field_mappings, default: {}, null: false
      t.timestamps
    end
    add_index_if_missing :campaigns, :slug, unique: true
    add_index_if_missing :campaigns, :theme
    add_index_if_missing :campaigns, :active
    add_index_if_missing :campaigns, :status
    add_index_if_missing :campaigns, :airtable_sync_enabled
    add_index_if_missing :campaigns, :subdomain, unique: true, where: "(subdomain IS NOT NULL)"

    # Campaign Assets
    create_table :campaign_assets, if_not_exists: true do |t|
      t.references :campaign, null: false, foreign_key: true
      t.string :name, null: false
      t.string :asset_type, null: false
      t.string :variant
      t.text :description
      t.jsonb :metadata, default: {}, null: false
      t.boolean :active, default: true, null: false
      t.timestamps
    end
    add_index_if_missing :campaign_assets, :active
    add_index_if_missing :campaign_assets, [ :campaign_id, :asset_type ]
    add_index_if_missing :campaign_assets, [ :campaign_id, :asset_type, :variant ],
                         unique: true, where: "(variant IS NOT NULL)",
                         name: "idx_on_campaign_id_asset_type_variant_b758d73b65"

    # API Keys
    create_table :api_keys, if_not_exists: true do |t|
      t.references :campaign, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :key_digest, null: false
      t.string :key_prefix, null: false
      t.jsonb :permissions, default: {}
      t.datetime :last_used_at
      t.integer :request_count, default: 0, null: false
      t.boolean :active, default: true, null: false
      t.timestamps
    end
    add_index_if_missing :api_keys, :key_digest, unique: true
    add_index_if_missing :api_keys, :key_prefix
    add_index_if_missing :api_keys, :active

    # Poster Groups
    create_table :poster_groups, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.references :campaign, null: false, foreign_key: true
      t.string :name
      t.integer :poster_count, default: 0, null: false
      t.string :charset, default: "alphanumeric"
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end
    add_index_if_missing :poster_groups, [ :user_id, :created_at ]
    add_index_if_missing :poster_groups, [ :campaign_id, :created_at ]

    # Posters
    create_table :posters, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.references :campaign, null: false, foreign_key: true
      t.references :poster_group, foreign_key: true
      t.string :qr_code_token, null: false
      t.string :referral_code
      t.string :poster_type, default: "color", null: false
      t.string :verification_status, default: "pending", null: false
      t.datetime :verified_at
      t.string :verified_by_type
      t.bigint :verified_by_id
      t.text :rejection_reason
      t.string :proof_image_url
      t.jsonb :detected_qr_codes, default: []
      t.string :location_description
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.string :country_code
      t.jsonb :metadata, default: {}
      t.timestamps
    end
    add_index_if_missing :posters, :qr_code_token, unique: true
    add_index_if_missing :posters, :referral_code, unique: true
    add_index_if_missing :posters, :verification_status
    add_index_if_missing :posters, [ :verified_by_type, :verified_by_id ]

    # Poster Scans
    create_table :poster_scans, if_not_exists: true do |t|
      t.references :poster, null: false, foreign_key: true
      t.string :ip_address
      t.string :user_agent
      t.jsonb :metadata, default: {}
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.string :city
      t.string :region
      t.string :country_code
      t.string :country_name
      t.string :postal_code
      t.string :org
      t.string :timezone
      t.datetime :geocoded_at
      t.timestamps
    end
    add_index_if_missing :poster_scans, :created_at
    add_index_if_missing :poster_scans, :country_code
    add_index_if_missing :poster_scans, :geocoded_at

    # Referrals
    create_table :referrals, if_not_exists: true do |t|
      t.references :referrer, null: false, foreign_key: { to_table: :users }
      t.references :referred, foreign_key: { to_table: :users }
      t.references :campaign, null: false, foreign_key: true
      t.string :referred_identifier, null: false
      t.string :referral_type, default: "link", null: false
      t.integer :status, default: 0, null: false
      t.integer :tracked_minutes, default: 0, null: false
      t.datetime :completed_at
      t.datetime :verified_at
      t.string :external_program
      t.jsonb :metadata, default: {}
      t.timestamps
    end
    add_index_if_missing :referrals, [ :referrer_id, :referred_identifier ], unique: true
    add_index_if_missing :referrals, :referred_identifier
    add_index_if_missing :referrals, :referral_type
    add_index_if_missing :referrals, :status
    add_index_if_missing :referrals, :external_program

    # Referral Code Logs
    create_table :referral_code_logs, if_not_exists: true do |t|
      t.string :referral_code, null: false
      t.string :ip_address, null: false
      t.string :user_agent
      t.jsonb :metadata, default: {}
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.string :city
      t.string :region
      t.string :country_code
      t.string :country_name
      t.string :postal_code
      t.string :org
      t.string :timezone
      t.datetime :geocoded_at
      t.timestamps
    end
    add_index_if_missing :referral_code_logs, :referral_code
    add_index_if_missing :referral_code_logs, :ip_address
    add_index_if_missing :referral_code_logs, :created_at
    add_index_if_missing :referral_code_logs, :country_code
    add_index_if_missing :referral_code_logs, :geocoded_at

    # Login Logs
    create_table :login_logs, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.string :ip_address, null: false
      t.string :user_agent
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.string :city
      t.string :region
      t.string :country_code
      t.string :country_name
      t.datetime :geocoded_at
      t.timestamps
    end
    add_index_if_missing :login_logs, :ip_address
    add_index_if_missing :login_logs, :created_at
    add_index_if_missing :login_logs, :country_code

    # Shard Transactions
    create_table :shard_transactions, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :amount, null: false
      t.integer :balance_after, null: false
      t.string :transaction_type, null: false
      t.text :description
      t.string :transactable_type
      t.bigint :transactable_id
      t.timestamps
    end
    add_index_if_missing :shard_transactions, :transaction_type
    add_index_if_missing :shard_transactions, :created_at
    add_index_if_missing :shard_transactions, [ :transactable_type, :transactable_id ],
                         name: "idx_on_transactable_type_transactable_id_29b231d81f"

    # Shop Items
    create_table :shop_items, if_not_exists: true do |t|
      t.string :name, null: false
      t.text :description
      t.string :category
      t.integer :price_shards, null: false
      t.integer :sale_price_shards
      t.boolean :on_sale, default: false, null: false
      t.integer :stock_quantity
      t.boolean :unlimited_stock, default: false, null: false
      t.integer :max_per_user
      t.string :image_url
      t.boolean :active, default: true, null: false
      t.boolean :is_physical, default: true, null: false
      t.integer :flavortown_id
      t.datetime :flavortown_synced_at
      t.boolean :enabled_us
      t.boolean :enabled_uk
      t.boolean :enabled_eu
      t.boolean :enabled_ca
      t.boolean :enabled_au
      t.boolean :enabled_in
      t.boolean :enabled_xx
      t.decimal :price_offset_us, precision: 10, scale: 2
      t.decimal :price_offset_uk, precision: 10, scale: 2
      t.decimal :price_offset_eu, precision: 10, scale: 2
      t.decimal :price_offset_ca, precision: 10, scale: 2
      t.decimal :price_offset_au, precision: 10, scale: 2
      t.decimal :price_offset_in, precision: 10, scale: 2
      t.decimal :price_offset_xx, precision: 10, scale: 2
      t.jsonb :metadata, default: {}
      t.timestamps
    end
    add_index_if_missing :shop_items, :active
    add_index_if_missing :shop_items, :category
    add_index_if_missing :shop_items, :price_shards
    add_index_if_missing :shop_items, :flavortown_id, unique: true, where: "(flavortown_id IS NOT NULL)"

    # Shop Orders
    create_table :shop_orders, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.references :shop_item, null: false, foreign_key: true
      t.integer :quantity, default: 1, null: false
      t.integer :total_shards, null: false
      t.string :status, default: "pending", null: false
      t.text :notes
      t.text :shipping_address
      t.text :admin_notes
      t.text :status_notes
      t.string :tracking_number
      t.string :tracking_url
      t.datetime :fulfilled_at
      t.references :fulfilled_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index_if_missing :shop_orders, :status
    add_index_if_missing :shop_orders, :created_at

    # User Emblems
    create_table :user_emblems, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true
      t.references :campaign, null: false, foreign_key: true
      t.string :emblem_type, null: false
      t.datetime :earned_at, null: false
      t.timestamps
    end
    add_index_if_missing :user_emblems, [ :user_id, :campaign_id, :emblem_type ], unique: true

    # Airtable Imports
    create_table :airtable_imports, if_not_exists: true do |t|
      t.string :table_name, null: false
      t.string :airtable_record_id, null: false
      t.string :importable_type, null: false
      t.bigint :importable_id, null: false
      t.jsonb :raw_data, default: {}
      t.datetime :last_imported_at
      t.timestamps
    end
    add_index_if_missing :airtable_imports, [ :table_name, :airtable_record_id ],
                         name: "index_airtable_imports_on_table_and_record", unique: true
    add_index_if_missing :airtable_imports, [ :importable_type, :importable_id ],
                         name: "index_airtable_imports_on_importable"
    add_index_if_missing :airtable_imports, :last_imported_at

    # Airtable Referrals
    create_table :airtable_referrals, if_not_exists: true do |t|
      t.string :airtable_record_id, null: false
      t.string :source_table, null: false
      t.references :campaign, foreign_key: true
      t.string :email, null: false
      t.string :name
      t.string :slack_id
      t.string :referral_code, null: false
      t.jsonb :metadata, default: {}
      t.datetime :synced_at
      t.timestamps
    end
    add_index_if_missing :airtable_referrals, :airtable_record_id, unique: true
    add_index_if_missing :airtable_referrals, :email
    add_index_if_missing :airtable_referrals, :slack_id
    add_index_if_missing :airtable_referrals, :referral_code
    add_index_if_missing :airtable_referrals, :source_table
    add_index_if_missing :airtable_referrals, :synced_at
    add_index_if_missing :airtable_referrals, [ :campaign_id, :email ]
    add_index_if_missing :airtable_referrals, [ :campaign_id, :referral_code ]

    # Airtable Sync Runs
    create_table :airtable_sync_runs, if_not_exists: true do |t|
      t.references :campaign, foreign_key: true
      t.string :status, null: false
      t.datetime :started_at
      t.datetime :finished_at
      t.float :duration_seconds
      t.jsonb :stats, default: {}, null: false
      t.text :message
      t.timestamps
    end
    add_index_if_missing :airtable_sync_runs, :status
    add_index_if_missing :airtable_sync_runs, :started_at

    # Geocode Runs
    create_table :geocode_runs, if_not_exists: true do |t|
      t.string :status, default: "running", null: false
      t.datetime :started_at
      t.datetime :finished_at
      t.decimal :duration_seconds, precision: 10, scale: 3
      t.integer :pending_before, default: 0
      t.integer :pending_after, default: 0
      t.integer :processed_count, default: 0
      t.integer :success_count, default: 0
      t.integer :failure_count, default: 0
      t.jsonb :stats, default: {}
      t.text :message
      t.timestamps
    end
    add_index_if_missing :geocode_runs, :status
    add_index_if_missing :geocode_runs, :started_at
  end

  private

  def add_index_if_missing(table, columns, **options)
    return if index_exists?(table, columns, **options.except(:name))

    add_index(table, columns, **options)
  end

  def add_fk_if_missing(from_table, to_table, **options)
    return if foreign_key_exists?(from_table, to_table, **options)

    add_foreign_key(from_table, to_table, **options)
  end
end
