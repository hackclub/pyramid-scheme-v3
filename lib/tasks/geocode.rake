# frozen_string_literal: true

namespace :geocode do
  desc "Backfill geolocation data for existing referral code logs"
  task backfill: :environment do
    batch_size = ENV.fetch("BATCH_SIZE", 100).to_i
    delay_ms = ENV.fetch("DELAY_MS", 100).to_i

    puts "Starting geocode backfill..."
    puts "Batch size: #{batch_size}, Delay between batches: #{delay_ms}ms"

    # Backfill referral code logs
    pending_logs = ReferralCodeLog.not_geocoded.count
    puts "\nReferral code logs pending: #{pending_logs}"

    ReferralCodeLog.not_geocoded.find_in_batches(batch_size: batch_size) do |batch|
      batch.each do |log|
        GeocodeIpJob.perform_later("ReferralCodeLog", log.id)
      end
      print "."
      sleep(delay_ms / 1000.0) if delay_ms > 0
    end

    # Backfill login logs
    pending_logins = LoginLog.not_geocoded.count
    puts "\n\nLogin logs pending: #{pending_logins}"

    LoginLog.not_geocoded.find_in_batches(batch_size: batch_size) do |batch|
      batch.each do |log|
        GeocodeIpJob.perform_later("LoginLog", log.id)
      end
      print "."
      sleep(delay_ms / 1000.0) if delay_ms > 0
    end

    puts "\n\nBackfill jobs enqueued!"
    puts "Jobs will process asynchronously. Check your job queue for progress."
  end

  desc "Geocode a single IP address (for testing)"
  task :test, [ :ip ] => :environment do |_t, args|
    ip = args[:ip] || "8.8.8.8"
    puts "Testing geocoding for IP: #{ip}"

    api_key = ENV["GEOCODER_API_KEY"]
    unless api_key.present?
      puts "ERROR: GEOCODER_API_KEY not set"
      exit 1
    end

    require "net/http"
    require "json"

    uri = URI("https://geocoder.hackclub.com/v1/geoip?ip=#{ip}&key=#{api_key}")
    response = Net::HTTP.get_response(uri)

    if response.is_a?(Net::HTTPSuccess)
      data = JSON.parse(response.body)
      puts "Response:"
      puts JSON.pretty_generate(data)
    else
      puts "ERROR: #{response.code} - #{response.body}"
    end
  end

  desc "Show geocoding statistics"
  task stats: :environment do
    puts "Geocoding Statistics"
    puts "=" * 40

    puts "\nReferral Code Logs:"
    puts "  Total: #{ReferralCodeLog.count}"
    puts "  Geocoded: #{ReferralCodeLog.geocoded.count}"
    puts "  Pending: #{ReferralCodeLog.not_geocoded.count}"

    puts "\nLogin Logs:"
    puts "  Total: #{LoginLog.count}"
    puts "  Geocoded: #{LoginLog.geocoded.count}"
    puts "  Pending: #{LoginLog.not_geocoded.count}"

    puts "\nTop Countries (Referral Logs):"
    ReferralCodeLog.geocoded
      .group(:country_name)
      .order("count_all DESC")
      .limit(10)
      .count
      .each { |country, count| puts "  #{country}: #{count}" }
  end
end
