# frozen_string_literal: true

# Keep users signed in across reloads by persisting the session cookie.
Rails.application.config.session_store :cookie_store,
  key: "_pyramid_session",
  expire_after: 2.weeks,
  secure: Rails.env.production?,
  same_site: :lax
