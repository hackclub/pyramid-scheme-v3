# frozen_string_literal: true

namespace :id_vault do
  desc "Reset ID Vault (delete all API keys). Set CONFIRM=1 to run."
  task reset: :environment do
    unless Rails.env.development? || Rails.env.test?
      abort "Refusing to run outside development/test."
    end

    unless ENV["CONFIRM"] == "1"
      abort "Set CONFIRM=1 to proceed (this deletes ALL rows in api_keys)."
    end

    deleted = ApiKey.delete_all
    puts "Deleted #{deleted} api_keys row(s)."
  end
end
