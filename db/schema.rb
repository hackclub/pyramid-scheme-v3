# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_01_17_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "airtable_imports", force: :cascade do |t|
    t.string "airtable_record_id", null: false
    t.datetime "created_at", null: false
    t.bigint "importable_id", null: false
    t.string "importable_type", null: false
    t.datetime "last_imported_at"
    t.jsonb "raw_data", default: {}
    t.string "table_name", null: false
    t.datetime "updated_at", null: false
    t.index ["importable_type", "importable_id"], name: "index_airtable_imports_on_importable"
    t.index ["last_imported_at"], name: "index_airtable_imports_on_last_imported_at"
    t.index ["table_name", "airtable_record_id"], name: "index_airtable_imports_on_table_and_record", unique: true
  end

  create_table "airtable_referrals", force: :cascade do |t|
    t.string "airtable_record_id", null: false
    t.bigint "campaign_id"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.jsonb "metadata", default: {}
    t.string "name"
    t.string "referral_code", null: false
    t.string "slack_id"
    t.string "source_table", null: false
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.index ["airtable_record_id"], name: "index_airtable_referrals_on_airtable_record_id", unique: true
    t.index ["campaign_id", "email"], name: "index_airtable_referrals_on_campaign_id_and_email"
    t.index ["campaign_id", "referral_code"], name: "index_airtable_referrals_on_campaign_id_and_referral_code"
    t.index ["campaign_id"], name: "index_airtable_referrals_on_campaign_id"
    t.index ["email"], name: "index_airtable_referrals_on_email"
    t.index ["referral_code"], name: "index_airtable_referrals_on_referral_code"
    t.index ["slack_id"], name: "index_airtable_referrals_on_slack_id"
    t.index ["source_table"], name: "index_airtable_referrals_on_source_table"
    t.index ["synced_at"], name: "index_airtable_referrals_on_synced_at"
  end

  create_table "airtable_sync_runs", force: :cascade do |t|
    t.bigint "campaign_id"
    t.datetime "created_at", null: false
    t.float "duration_seconds"
    t.datetime "finished_at"
    t.text "message"
    t.datetime "started_at"
    t.jsonb "stats", default: {}, null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id"], name: "index_airtable_sync_runs_on_campaign_id"
    t.index ["started_at"], name: "index_airtable_sync_runs_on_started_at"
    t.index ["status"], name: "index_airtable_sync_runs_on_status"
  end

  create_table "api_keys", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.bigint "campaign_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key_digest", null: false
    t.string "key_prefix", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.jsonb "permissions", default: {}
    t.integer "request_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_api_keys_on_active"
    t.index ["campaign_id"], name: "index_api_keys_on_campaign_id"
    t.index ["key_digest"], name: "index_api_keys_on_key_digest", unique: true
    t.index ["key_prefix"], name: "index_api_keys_on_key_prefix"
  end

  create_table "campaign_assets", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "asset_type", null: false
    t.bigint "campaign_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.string "variant"
    t.index ["active"], name: "index_campaign_assets_on_active"
    t.index ["campaign_id", "asset_type", "variant"], name: "idx_on_campaign_id_asset_type_variant_b758d73b65", unique: true, where: "(variant IS NOT NULL)"
    t.index ["campaign_id", "asset_type"], name: "index_campaign_assets_on_campaign_id_and_asset_type"
    t.index ["campaign_id"], name: "index_campaign_assets_on_campaign_id"
  end

  create_table "campaigns", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "airtable_base_id"
    t.jsonb "airtable_field_mappings", default: {}, null: false
    t.boolean "airtable_sync_enabled", default: false, null: false
    t.string "airtable_table_id"
    t.string "base_url"
    t.datetime "created_at", null: false
    t.text "custom_css"
    t.text "description"
    t.datetime "ends_at"
    t.jsonb "i18n_overrides", default: {}, null: false
    t.string "name", null: false
    t.jsonb "poster_qr_coordinates", default: {}, null: false
    t.integer "poster_shards", default: 1, null: false
    t.jsonb "poster_templates", default: {}, null: false
    t.integer "referral_shards", default: 3, null: false
    t.integer "required_coding_minutes", default: 60, null: false
    t.string "slug", null: false
    t.datetime "starts_at"
    t.string "status", default: "open", null: false
    t.string "subdomain"
    t.string "theme", null: false
    t.jsonb "theme_config", default: {}
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_campaigns_on_active"
    t.index ["airtable_sync_enabled"], name: "index_campaigns_on_airtable_sync_enabled"
    t.index ["slug"], name: "index_campaigns_on_slug", unique: true
    t.index ["status"], name: "index_campaigns_on_status"
    t.index ["subdomain"], name: "index_campaigns_on_subdomain", unique: true, where: "(subdomain IS NOT NULL)"
    t.index ["theme"], name: "index_campaigns_on_theme"
  end

  create_table "geocode_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "duration_seconds", precision: 10, scale: 3
    t.integer "failure_count", default: 0
    t.datetime "finished_at"
    t.text "message"
    t.integer "pending_after", default: 0
    t.integer "pending_before", default: 0
    t.integer "processed_count", default: 0
    t.datetime "started_at"
    t.jsonb "stats", default: {}
    t.string "status", default: "running", null: false
    t.integer "success_count", default: 0
    t.datetime "updated_at", null: false
    t.index ["started_at"], name: "index_geocode_runs_on_started_at"
    t.index ["status"], name: "index_geocode_runs_on_status"
  end

  create_table "login_logs", force: :cascade do |t|
    t.string "city"
    t.string "country_code"
    t.string "country_name"
    t.datetime "created_at", null: false
    t.datetime "geocoded_at"
    t.string "ip_address", null: false
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.string "region"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["country_code"], name: "index_login_logs_on_country_code"
    t.index ["created_at"], name: "index_login_logs_on_created_at"
    t.index ["ip_address"], name: "index_login_logs_on_ip_address"
    t.index ["user_id"], name: "index_login_logs_on_user_id"
  end

  create_table "poster_groups", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.string "charset", default: "alphanumeric"
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "name"
    t.integer "poster_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["campaign_id", "created_at"], name: "index_poster_groups_on_campaign_id_and_created_at"
    t.index ["campaign_id"], name: "index_poster_groups_on_campaign_id"
    t.index ["user_id", "created_at"], name: "index_poster_groups_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_poster_groups_on_user_id"
  end

  create_table "poster_scans", force: :cascade do |t|
    t.string "city"
    t.string "country_code"
    t.string "country_name"
    t.datetime "created_at", null: false
    t.datetime "geocoded_at"
    t.string "ip_address"
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.jsonb "metadata", default: {}
    t.string "org"
    t.string "postal_code"
    t.bigint "poster_id", null: false
    t.string "region"
    t.string "timezone"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["country_code"], name: "index_poster_scans_on_country_code"
    t.index ["created_at"], name: "index_poster_scans_on_created_at"
    t.index ["geocoded_at"], name: "index_poster_scans_on_geocoded_at"
    t.index ["poster_id"], name: "index_poster_scans_on_poster_id"
  end

  create_table "posters", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.string "country_code"
    t.datetime "created_at", null: false
    t.jsonb "detected_qr_codes", default: []
    t.decimal "latitude", precision: 10, scale: 6
    t.string "location_description"
    t.decimal "longitude", precision: 10, scale: 6
    t.jsonb "metadata", default: {}
    t.bigint "poster_group_id"
    t.integer "poster_scans_count", default: 0, null: false
    t.string "poster_type", default: "color", null: false
    t.string "proof_image_url"
    t.string "qr_code_token", null: false
    t.string "referral_code"
    t.text "rejection_reason"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "verification_status", default: "pending", null: false
    t.datetime "verified_at"
    t.bigint "verified_by_id"
    t.string "verified_by_type"
    t.index ["campaign_id"], name: "index_posters_on_campaign_id"
    t.index ["poster_group_id"], name: "index_posters_on_poster_group_id"
    t.index ["qr_code_token"], name: "index_posters_on_qr_code_token", unique: true
    t.index ["referral_code"], name: "index_posters_on_referral_code", unique: true
    t.index ["user_id", "campaign_id", "verification_status"], name: "idx_posters_user_campaign_status"
    t.index ["user_id"], name: "index_posters_on_user_id"
    t.index ["verification_status"], name: "index_posters_on_verification_status"
    t.index ["verified_by_type", "verified_by_id"], name: "index_posters_on_verified_by_type_and_verified_by_id"
  end

  create_table "referral_code_logs", force: :cascade do |t|
    t.string "city"
    t.string "country_code"
    t.string "country_name"
    t.datetime "created_at", null: false
    t.datetime "geocoded_at"
    t.string "ip_address", null: false
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.jsonb "metadata", default: {}
    t.string "org"
    t.string "postal_code"
    t.string "referral_code", null: false
    t.string "region"
    t.string "timezone"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["country_code"], name: "index_referral_code_logs_on_country_code"
    t.index ["created_at"], name: "index_referral_code_logs_on_created_at"
    t.index ["geocoded_at"], name: "index_referral_code_logs_on_geocoded_at"
    t.index ["ip_address"], name: "index_referral_code_logs_on_ip_address"
    t.index ["referral_code"], name: "index_referral_code_logs_on_referral_code"
  end

  create_table "referrals", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "external_program"
    t.jsonb "metadata", default: {}
    t.string "referral_type", default: "link", null: false
    t.bigint "referred_id"
    t.string "referred_identifier", null: false
    t.bigint "referrer_id", null: false
    t.integer "status", default: 0, null: false
    t.integer "tracked_minutes", default: 0, null: false
    t.datetime "updated_at", null: false
    t.datetime "verified_at"
    t.index ["campaign_id", "status", "referral_type"], name: "idx_referrals_campaign_status_type"
    t.index ["campaign_id"], name: "index_referrals_on_campaign_id"
    t.index ["external_program"], name: "index_referrals_on_external_program"
    t.index ["referral_type"], name: "index_referrals_on_referral_type"
    t.index ["referred_id"], name: "index_referrals_on_referred_id"
    t.index ["referred_identifier"], name: "index_referrals_on_referred_identifier"
    t.index ["referrer_id", "referred_identifier"], name: "index_referrals_on_referrer_id_and_referred_identifier", unique: true
    t.index ["referrer_id"], name: "index_referrals_on_referrer_id"
    t.index ["status"], name: "index_referrals_on_status"
  end

  create_table "shard_transactions", force: :cascade do |t|
    t.integer "amount", null: false
    t.integer "balance_after", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "transactable_id"
    t.string "transactable_type"
    t.string "transaction_type", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["created_at"], name: "index_shard_transactions_on_created_at"
    t.index ["transactable_type", "transactable_id"], name: "idx_on_transactable_type_transactable_id_29b231d81f"
    t.index ["transaction_type"], name: "index_shard_transactions_on_transaction_type"
    t.index ["user_id"], name: "index_shard_transactions_on_user_id"
  end

  create_table "shop_items", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "category"
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enabled_au"
    t.boolean "enabled_ca"
    t.boolean "enabled_eu"
    t.boolean "enabled_in"
    t.boolean "enabled_uk"
    t.boolean "enabled_us"
    t.boolean "enabled_xx"
    t.integer "flavortown_id"
    t.datetime "flavortown_synced_at"
    t.string "image_url"
    t.boolean "is_physical", default: true, null: false
    t.integer "max_per_user"
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.boolean "on_sale", default: false, null: false
    t.decimal "price_offset_au", precision: 10, scale: 2
    t.decimal "price_offset_ca", precision: 10, scale: 2
    t.decimal "price_offset_eu", precision: 10, scale: 2
    t.decimal "price_offset_in", precision: 10, scale: 2
    t.decimal "price_offset_uk", precision: 10, scale: 2
    t.decimal "price_offset_us", precision: 10, scale: 2
    t.decimal "price_offset_xx", precision: 10, scale: 2
    t.integer "price_shards", null: false
    t.integer "sale_price_shards"
    t.integer "stock_quantity"
    t.boolean "unlimited_stock", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_shop_items_on_active"
    t.index ["category"], name: "index_shop_items_on_category"
    t.index ["flavortown_id"], name: "index_shop_items_on_flavortown_id", unique: true, where: "(flavortown_id IS NOT NULL)"
    t.index ["price_shards"], name: "index_shop_items_on_price_shards"
  end

  create_table "shop_orders", force: :cascade do |t|
    t.text "admin_notes"
    t.datetime "created_at", null: false
    t.datetime "fulfilled_at"
    t.bigint "fulfilled_by_id"
    t.text "notes"
    t.integer "quantity", default: 1, null: false
    t.text "shipping_address"
    t.bigint "shop_item_id", null: false
    t.string "status", default: "pending", null: false
    t.text "status_notes"
    t.integer "total_shards", null: false
    t.string "tracking_number"
    t.string "tracking_url"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["created_at"], name: "index_shop_orders_on_created_at"
    t.index ["fulfilled_by_id"], name: "index_shop_orders_on_fulfilled_by_id"
    t.index ["shop_item_id"], name: "index_shop_orders_on_shop_item_id"
    t.index ["status"], name: "index_shop_orders_on_status"
    t.index ["user_id"], name: "index_shop_orders_on_user_id"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "key", null: false
    t.bigint "key_hash", null: false
    t.binary "value", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "user_emblems", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.datetime "created_at", null: false
    t.datetime "earned_at", null: false
    t.string "emblem_type", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["campaign_id"], name: "index_user_emblems_on_campaign_id"
    t.index ["user_id", "campaign_id", "emblem_type"], name: "index_user_emblems_on_user_id_and_campaign_id_and_emblem_type", unique: true
    t.index ["user_id"], name: "index_user_emblems_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "avatar"
    t.datetime "banned_at"
    t.text "banned_reason"
    t.integer "bonus_paid_posters", default: 0, null: false
    t.string "city"
    t.string "country_code"
    t.string "country_name"
    t.datetime "created_at", null: false
    t.string "custom_referral_code"
    t.datetime "custom_referral_code_changed_at"
    t.string "display_name", null: false
    t.string "email", null: false
    t.string "first_name"
    t.datetime "geocoded_at"
    t.text "internal_ban_reason"
    t.text "internal_notes"
    t.boolean "is_banned", default: false, null: false
    t.string "last_ip_address"
    t.string "last_name"
    t.datetime "last_seen_at"
    t.decimal "latitude", precision: 10, scale: 6
    t.boolean "leaderboard_opted_out", default: false, null: false
    t.decimal "longitude", precision: 10, scale: 6
    t.string "org"
    t.string "postal_code"
    t.integer "poster_count", default: 0, null: false
    t.string "referral_code"
    t.integer "referral_count", default: 0, null: false
    t.string "region"
    t.integer "role", default: 0, null: false
    t.string "signup_ref_source", limit: 64
    t.string "slack_id"
    t.string "timezone"
    t.integer "total_shards", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["banned_at"], name: "index_users_on_banned_at"
    t.index ["custom_referral_code"], name: "index_users_on_custom_referral_code", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["geocoded_at"], name: "index_users_on_geocoded_at"
    t.index ["last_seen_at"], name: "index_users_on_last_seen_at"
    t.index ["latitude"], name: "index_users_on_latitude"
    t.index ["leaderboard_opted_out"], name: "index_users_on_leaderboard_opted_out"
    t.index ["longitude"], name: "index_users_on_longitude"
    t.index ["poster_count"], name: "index_users_on_poster_count"
    t.index ["referral_code"], name: "index_users_on_referral_code", unique: true
    t.index ["referral_count"], name: "index_users_on_referral_count"
    t.index ["role"], name: "index_users_on_role"
    t.index ["signup_ref_source"], name: "index_users_on_signup_ref_source"
    t.index ["slack_id"], name: "index_users_on_slack_id", unique: true
    t.index ["total_shards"], name: "index_users_on_total_shards"
  end

  create_table "video_submissions", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.datetime "created_at", null: false
    t.boolean "is_viral", default: false, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "reviewed_at"
    t.bigint "reviewed_by_id"
    t.text "reviewer_notes"
    t.integer "shards_awarded", default: 0, null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "video_url"
    t.integer "viral_bonus", default: 0, null: false
    t.datetime "virality_checked_at"
    t.bigint "virality_checked_by_id"
    t.string "virality_status", default: "pending", null: false
    t.index ["campaign_id", "status"], name: "index_video_submissions_on_campaign_id_and_status"
    t.index ["campaign_id"], name: "index_video_submissions_on_campaign_id"
    t.index ["reviewed_by_id"], name: "index_video_submissions_on_reviewed_by_id"
    t.index ["status"], name: "index_video_submissions_on_status"
    t.index ["user_id", "created_at"], name: "index_video_submissions_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_video_submissions_on_user_id"
    t.index ["virality_checked_by_id"], name: "index_video_submissions_on_virality_checked_by_id"
    t.index ["virality_status"], name: "index_video_submissions_on_virality_status"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "airtable_referrals", "campaigns"
  add_foreign_key "airtable_sync_runs", "campaigns"
  add_foreign_key "api_keys", "campaigns"
  add_foreign_key "campaign_assets", "campaigns"
  add_foreign_key "login_logs", "users"
  add_foreign_key "poster_groups", "campaigns"
  add_foreign_key "poster_groups", "users"
  add_foreign_key "poster_scans", "posters"
  add_foreign_key "posters", "campaigns"
  add_foreign_key "posters", "poster_groups"
  add_foreign_key "posters", "users"
  add_foreign_key "referrals", "campaigns"
  add_foreign_key "referrals", "users", column: "referred_id"
  add_foreign_key "referrals", "users", column: "referrer_id"
  add_foreign_key "shard_transactions", "users"
  add_foreign_key "shop_orders", "shop_items"
  add_foreign_key "shop_orders", "users"
  add_foreign_key "shop_orders", "users", column: "fulfilled_by_id"
  add_foreign_key "user_emblems", "campaigns"
  add_foreign_key "user_emblems", "users"
  add_foreign_key "video_submissions", "campaigns"
  add_foreign_key "video_submissions", "users"
  add_foreign_key "video_submissions", "users", column: "reviewed_by_id"
  add_foreign_key "video_submissions", "users", column: "virality_checked_by_id"
end
