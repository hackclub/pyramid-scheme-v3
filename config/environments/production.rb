require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Use environment variable for secret key base in production
  # Allow SECRET_KEY_BASE_DUMMY for asset precompilation during Docker build
  config.secret_key_base = ENV["SECRET_KEY_BASE_DUMMY"] ? "dummy" : ENV["SECRET_KEY_BASE"]

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on Cloudflare R2 (S3-compatible)
  # Azure is down; all new uploads go to R2 only.
  # Old files on Azure are still readable via the azure service config in storage.yml.
  config.active_storage.service = :r2

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  # config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  # config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # ActiveJob queue adapter is set in config/initializers/active_job.rb

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by links generated in mailer templates and helpers.
  # Resolve early here so assets:precompile works even when initializers haven't set config.x.app_host yet.
  default_app_host = ENV["DEFAULT_APP_HOST"].presence || "https://pyramid.hackclub.com"
  raw_app_host = ENV["APP_HOST"].presence
  safe_warn = ->(message) do
    logger = Rails.logger
    if logger
      logger.warn(message)
    else
      ::Kernel.warn(message)
    end
  end

  app_host = begin
    candidate = raw_app_host.presence || default_app_host
    host = URI.parse(candidate).host

    if host.blank? || host.match?(/\A(localhost|127\.0\.0\.1|0\.0\.0\.0)\z/i)
      safe_warn.call("APP_HOST points to localhost or is invalid for production; using #{default_app_host}")
      candidate = default_app_host
    end

    candidate
  rescue URI::InvalidURIError
    safe_warn.call("APP_HOST is invalid: #{raw_app_host.inspect}, using #{default_app_host}")
    default_app_host
  end

  app_host_uri = URI.parse(app_host)
  config.x.app_host = app_host
  config.action_controller.default_url_options = {
    host: app_host_uri.host,
    port: app_host_uri.port,
    protocol: app_host_uri.scheme
  }
  config.action_mailer.default_url_options = {
    host: app_host_uri.host,
    port: app_host_uri.port,
    protocol: app_host_uri.scheme
  }

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via bin/rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
