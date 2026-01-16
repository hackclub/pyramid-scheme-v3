#!/usr/bin/env ruby
# frozen_string_literal: true

# Standalone script to backfill geocoding data directly against production database
# Usage: DATABASE_URL=... GEOCODER_API_KEY=... ruby scripts/geocode_backfill.rb

require "pg"
require "net/http"
require "json"
require "uri"
require "ipaddr"

DATABASE_URL = ENV["DATABASE_URL"] || raise("DATABASE_URL required")
GEOCODER_API_KEY = ENV["GEOCODER_API_KEY"] || raise("GEOCODER_API_KEY required")
GEOCODER_API_URL = "https://geocoder.hackclub.com/v1/geoip"
BATCH_SIZE = (ENV["BATCH_SIZE"] || 50).to_i
DELAY_MS = (ENV["DELAY_MS"] || 200).to_i

PRIVATE_IP_RANGES = [
  IPAddr.new("10.0.0.0/8"),
  IPAddr.new("172.16.0.0/12"),
  IPAddr.new("192.168.0.0/16"),
  IPAddr.new("127.0.0.0/8"),
  IPAddr.new("169.254.0.0/16")
].freeze

def private_ip?(ip_string)
  return true if ip_string.nil? || ip_string.empty? || ip_string == "unknown"

  ip = IPAddr.new(ip_string)
  PRIVATE_IP_RANGES.any? { |range| range.include?(ip) }
rescue IPAddr::InvalidAddressError
  true
end

def fetch_geocoding(ip_address)
  return nil if private_ip?(ip_address)

  uri = URI("#{GEOCODER_API_URL}?ip=#{ip_address}&key=#{GEOCODER_API_KEY}")
  response = Net::HTTP.get_response(uri)

  return nil unless response.is_a?(Net::HTTPSuccess)

  JSON.parse(response.body)
rescue => e
  puts "  Error geocoding #{ip_address}: #{e.message}"
  nil
end

def geocode_table(conn, table_name, ip_column = "ip_address")
  puts "\n=== Processing #{table_name} ==="

  # Count pending
  result = conn.exec("SELECT COUNT(*) FROM #{table_name} WHERE geocoded_at IS NULL")
  pending = result[0]["count"].to_i
  puts "Pending: #{pending}"

  return if pending == 0

  processed = 0
  geocoded = 0
  skipped = 0

  loop do
    # Fetch batch
    result = conn.exec_params(
      "SELECT id, #{ip_column} FROM #{table_name} WHERE geocoded_at IS NULL LIMIT $1",
      [ BATCH_SIZE ]
    )

    break if result.ntuples == 0

    result.each do |row|
      id = row["id"]
      ip = row[ip_column]

      if private_ip?(ip)
        # Mark as geocoded but with no data (private IP)
        conn.exec_params(
          "UPDATE #{table_name} SET geocoded_at = NOW() WHERE id = $1",
          [ id ]
        )
        skipped += 1
        processed += 1
        print "s"
        next
      end

      geo = fetch_geocoding(ip)

      if geo
        conn.exec_params(
          "UPDATE #{table_name} SET
            latitude = $1, longitude = $2, city = $3, region = $4,
            country_name = $5, country_code = $6, postal_code = $7,
            timezone = $8, org = $9, geocoded_at = NOW()
          WHERE id = $10",
          [
            geo["lat"], geo["lng"], geo["city"], geo["region"],
            geo["country_name"], geo["country_code"], geo["postal_code"],
            geo["timezone"], geo["org"], id
          ]
        )
        geocoded += 1
        print "."
      else
        # Mark as attempted even if failed
        conn.exec_params(
          "UPDATE #{table_name} SET geocoded_at = NOW() WHERE id = $1",
          [ id ]
        )
        skipped += 1
        print "x"
      end

      processed += 1
      sleep(DELAY_MS / 1000.0) if DELAY_MS > 0
    end

    puts " (#{processed}/#{pending})"
  end

  puts "\nCompleted #{table_name}: #{geocoded} geocoded, #{skipped} skipped"
end

# Main
puts "Geocode Backfill Script"
puts "=" * 40
puts "Database: #{DATABASE_URL.gsub(/:[^:@]+@/, ':***@')}"
puts "Batch size: #{BATCH_SIZE}"
puts "Delay: #{DELAY_MS}ms"

conn = PG.connect(DATABASE_URL)

begin
  geocode_table(conn, "referral_code_logs")
  geocode_table(conn, "login_logs")
ensure
  conn.close
end

puts "\n\nDone!"
