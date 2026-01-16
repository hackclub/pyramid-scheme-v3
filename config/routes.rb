# frozen_string_literal: true

Rails.application.routes.draw do
  # Health checks - custom controller that checks migrations and DB connectivity
  get "up" => "health#show", as: :rails_health_check
  get "healthy" => "health#show"

  # Root path - landing page for guests, dashboard for signed-in users
  root "landing#index"

  # Proxy routes for referral links (typically on flavortown.hackclub.com subdomain)
  # Poster referrals: flavortown.hackclub.com/p/:code (8 char uppercase)
  # Regular referrals: flavortown.hackclub.com/:code (direct links only, no /r/ prefix)
  get "/avatar", to: "proxy#avatar", as: :avatar_proxy

  # Authentication
  get "/auth/hackclub", to: "sessions#new", as: :auth
  get "/oauth/callback", to: "sessions#create", as: :auth_callback
  get "/auth/failure", to: "sessions#failure"
  delete "/logout", to: "sessions#destroy", as: :logout

  # Dashboard
  get "/dashboard", to: "dashboard#index", as: :dashboard

  # Campaigns
  get "/campaigns", to: "campaigns#index", as: :campaigns
  get "/c/:slug", to: "campaigns#show", as: :campaign

  # Video submissions (nested under campaign for context)
  post "/c/:campaign_slug/videos", to: "video_submissions#create", as: :campaign_video_submissions
  delete "/videos/:id", to: "video_submissions#destroy", as: :video_submission
  post "/videos/:id/virality_check", to: "video_submissions#request_virality_check", as: :video_submission_virality_check

  # Posters (index and new removed - use modals on campaign page instead)
  resources :posters, only: [ :create, :show, :edit, :update, :destroy ] do
    member do
      get :download
      post :upload_proof
      post :mark_digital
      patch :update_location
      post :submit
    end
  end

  # Poster Groups (bulk poster generation)
  resources :poster_groups, only: [ :create, :show, :update, :destroy ] do
    member do
      post :submit_all
      post :auto_detect
    end
  end

  # Poster routes - handle both QR scans (12 char) and referral codes (8 char uppercase)
  # QR scan uses the full qr_code_token (12 chars)
  get "/p/:code", to: "posters#handle_poster_link", as: :poster_link

  # Shop
  get "/shop", to: "shop#index", as: :shop
  patch "/shop/region", to: "shop#update_region", as: :shop_update_region
  get "/shop/:id", to: "shop#show", as: :shop_item

  resources :shop_orders, only: [ :index, :show, :create ]

  # Leaderboard
  get "/leaderboard", to: "leaderboard#index", as: :leaderboard

  # Map
  get "/map", to: "map#index", as: :map

  # Settings
  get "/settings", to: "settings#index", as: :settings
  patch "/settings", to: "settings#update"

  # Custom referral links
  patch "/custom_link", to: "custom_links#update", as: :custom_link
  get "/custom_link/validate", to: "custom_links#validate", as: :validate_custom_link

  # HCAuth (used by the web app; session-authenticated)
  get "/hcauth/addresses", to: "hcauth#addresses"

  # API v1
  namespace :api do
    namespace :v1 do
      resources :referrals, only: [ :index, :show ]
      get "referrals_valid", to: "referrals#referrals_valid"

      # Referral code validation endpoints
      resources :codes, only: [ :index, :show ]

      # Worker API (internal service communication)
      namespace :worker do
        get "/status", to: "/api/v1/worker#status"
        post "/jobs/airtable_sync", to: "/api/v1/worker#trigger_airtable_sync"
        post "/jobs/geocode", to: "/api/v1/worker#trigger_geocode"
        get "/jobs/airtable_sync/runs", to: "/api/v1/worker#airtable_sync_runs"
      end
    end
  end

  # Banned page
  get "/banned", to: "banned#show", as: :banned

  # Admin namespace
  namespace :admin do
    root "dashboard#index"

    # Impersonation
    post "impersonate/:user_id", to: "impersonations#create", as: :impersonate_user
    delete "stop_impersonating", to: "impersonations#destroy", as: :stop_impersonating

    post "airtable_sync/run", to: "airtable_sync#run", as: :run_airtable_sync

    # Statistics
    get "statistics", to: "statistics#index", as: :statistics
    get "statistics/data", to: "statistics#data", as: :statistics_data

    # Progress (v2 vs v3 comparison)
    get "progress", to: "progress#index", as: :progress
    get "progress/data", to: "progress#data", as: :progress_data

    # Geographic data
    get "geo", to: "geo#index", as: :geo

    resources :users, only: [ :index, :show, :edit, :update, :destroy ] do
      member do
        post :grant_shards
        post :debit_shards
        post :ban
        post :unban
        post :wipe_data
        post :promote_to_admin
        post :demote_from_admin
      end
    end

    resources :campaigns do
      resources :assets, controller: "campaign_assets" do
        member do
          post :generate_preview
        end
      end

      # Airtable configuration per campaign
      resource :airtable_config, only: [ :show, :update ], controller: "airtable_config" do
        post :sync
        post :test_connection
      end
    end

    # Global Airtable configuration
    resources :airtable_config, only: [ :index ] do
      collection do
        get :bases
        get "bases/:base_id/tables", action: :tables, as: :base_tables
      end
    end

    resources :api_keys, only: [ :index, :new, :create, :destroy ]

    resources :referrals, only: [ :index, :show, :destroy ] do
      member do
        post :verify
        post :complete
        post :update_minutes
      end
    end

    resources :referral_sources, only: [ :index ]

    resources :posters, only: [ :index, :show ] do
      member do
        post :verify
        post :hold
        post :reject
        post :mark_digital
        post :retry_auto_verify
        post :request_resubmission
      end
    end

    resources :shop_items
    resources :shop_orders, only: [ :index, :show ] do
      member do
        post :approve
        post :fulfill
        post :cancel
        post :mark_in_review
        post :mark_on_hold
        patch :update_notes
      end
    end

    resources :video_submissions, only: [ :index, :show ] do
      member do
        post :approve
        post :hold
        post :reject
        post :complete_virality
      end
    end
  end

  # Error pages
  match "/404", to: "errors#not_found", via: :all
  match "/422", to: "errors#unprocessable_entity", via: :all
  match "/500", to: "errors#internal_server_error", via: :all

  # Catch-all route for direct referral links /:code
  # MUST be last to avoid conflicts with other routes
  get "/:code", to: "proxy#link_referral", as: :direct_referral_proxy, constraints: { code: /[A-Za-z0-9]{4,12}/ }
end
