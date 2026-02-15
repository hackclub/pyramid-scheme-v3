# frozen_string_literal: true

require "faraday"
require "pg"
require "stringio"

namespace :shop do
  desc "Upload product images from local files to R2/storage service"
  task upload_local_images: :environment do
    # Local images saved in tmp/shop_images/
    local_images_dir = Rails.root.join("tmp/shop_images")

    unless Dir.exist?(local_images_dir)
      puts "ERROR: #{local_images_dir} does not exist. Download images first."
      exit 1
    end

    storage_service = ActiveStorage::Blob.service
    uploaded_urls = {}

    Dir.glob(local_images_dir.join("*.{webp,png,jpg,jpeg}")).each do |filepath|
      filename = File.basename(filepath)
      target_filename = filename.sub(/\.(webp|jpg|jpeg)$/, ".png") # normalize extension

      puts "Processing #{filename}..."

      begin
        content = File.read(filepath, mode: "rb")
        content_type = case File.extname(filepath).downcase
        when ".webp" then "image/webp"
        when ".png" then "image/png"
        when ".jpg", ".jpeg" then "image/jpeg"
        else "application/octet-stream"
        end

        key = "shop/#{target_filename}"
        io = StringIO.new(content)

        puts "  Uploading to storage as #{key}"
        storage_service.upload(key, io, content_type: content_type, filename: target_filename)

        # Get public URL based on service type
        public_url = if storage_service.respond_to?(:public_url)
          storage_service.public_url(key)
        else
          # For S3/R2, construct the URL
          bucket = ENV.fetch("R2_BUCKET", "pyramid")
          "#{ENV['R2_PUBLIC_URL']}/#{key}"
        end

        uploaded_urls[target_filename] = public_url
        puts "  Uploaded: #{public_url}"
      rescue => e
        puts "  ERROR: #{e.message}"
        puts "  #{e.backtrace.first(3).join("\n  ")}"
      end
    end

    puts "\n" + "=" * 80
    puts "UPLOAD SUMMARY"
    puts "=" * 80
    uploaded_urls.each { |filename, url| puts "#{filename}: #{url}" }
  end

  desc "Update prod database shop items with R2 URLs"
  task update_prod_urls: :environment do
    # Mapping of image filenames to R2 public URLs
    r2_base_url = ENV.fetch("R2_PUBLIC_URL") do
      puts "ERROR: R2_PUBLIC_URL environment variable not set"
      exit 1
    end

    prod_db_url = ENV.fetch("PROD_DATABASE_URL") do
      puts "ERROR: PROD_DATABASE_URL environment variable not set"
      exit 1
    end

    # Image filename mappings (what's in the DB vs what we uploaded)
    image_mappings = {
      "pile_of_stickers.png" => "pile_of_stickers.png",
      "cloudflare_credits.png" => "cloudflare_credits.png",
      "ai_credits.png" => "ai_credits.png",
      "domain_grant.png" => "domain_grant.png",
      "cloud_hosting_credits.png" => "cloud_hosting_credits.png",
      "ifixit_credits.png" => "ifixit_credits.png",
      "pcb_credits.png" => "pcb_credits.png",
      "smolhaj.png" => "smolhaj.png",
      "pinecil.png" => "pinecil.png",
      "github_notebook.png" => "github_notebook.png",
      "yubikey.png" => "yubikey.png",
      "raspberry_pi_5.png" => "raspberry_pi_5.png",
      "mac_mini.png" => "mac_mini.png",
      "framework_laptop_12.png" => "framework_laptop_12.png"
    }

    puts "Connecting to production database..."
    conn = PG.connect(prod_db_url)

    puts "Updating shop item image URLs to R2..."
    puts "=" * 80

    image_mappings.each do |old_filename, new_filename|
      new_url = "#{r2_base_url}/shop/#{new_filename}"
      old_pattern = "%/shop/#{old_filename}"

      result = conn.exec_params(
        "UPDATE shop_items SET image_url = $1, updated_at = NOW() WHERE image_url LIKE $2 RETURNING id, name",
        [ new_url, old_pattern ]
      )

      if result.ntuples > 0
        result.each { |row| puts "Updated #{row['name']} (id: #{row['id']}) -> #{new_url}" }
      end
    end

    conn.close
    puts "=" * 80
    puts "Done!"
  end

  desc "Download and upload product images from Flavortown to storage (R2)"
  task upload_flavortown_images: :environment do
    # Product images from Flavortown with their actual ActiveStorage URLs
    images = {
      "smolhaj.png" => "https://flavortown.hackclub.com/rails/active_storage/representations/proxy/eyJfcmFpbHMiOnsiZGF0YSI6MjM1LCJwdXIiOiJibG9iX2lkIn19--34b25d54db53c692f44b9f67a4c1f6ffd2eb391c/eyJfcmFpbHMiOnsiZGF0YSI6eyJmb3JtYXQiOiJ3ZWJwIiwicmVzaXplX3RvX2xpbWl0IjpbMzYwLG51bGxdLCJzYXZlciI6eyJzdHJpcCI6dHJ1ZSwicXVhbGl0eSI6NzV9fSwicHVyIjoidmFyaWF0aW9uIn19--d6a39ad4705dc76c8821affe402d334558212c92/blahaj.png",
      "pile_of_stickers.png" => "https://flavortown.hackclub.com/rails/active_storage/representations/proxy/eyJfcmFpbHMiOnsiZGF0YSI6NTMyLCJwdXIiOiJibG9iX2lkIn19--00960983352d912aa3d30bbee91e810628fffb7f/eyJfcmFpbHMiOnsiZGF0YSI6eyJmb3JtYXQiOiJ3ZWJwIiwicmVzaXplX3RvX2xpbWl0IjpbMzYwLG51bGxdLCJzYXZlciI6eyJzdHJpcCI6dHJ1ZSwicXVhbGl0eSI6NzV9fSwicHVyIjoidmFyaWF0aW9uIn19--d6a39ad4705dc76c8821affe402d334558212c92/pile_of_stickers.png",
      "cloudflare_credits.png" => "https://flavortown.hackclub.com/rails/active_storage/representations/proxy/eyJfcmFpbHMiOnsiZGF0YSI6MTY3NiwicHVyIjoiYmxvYl9pZCJ9fQ==--fe3c5b28fa91d75810ac735d9de131c63acbd993/eyJfcmFpbHMiOnsiZGF0YSI6eyJmb3JtYXQiOiJ3ZWJwIiwicmVzaXplX3RvX2xpbWl0IjpbMzYwLG51bGxdLCJzYXZlciI6eyJzdHJpcCI6dHJ1ZSwicXVhbGl0eSI6NzV9fSwicHVyIjoidmFyaWF0aW9uIn19--d6a39ad4705dc76c8821affe402d334558212c92/cf.png",
      "ai_credits.png" => "https://flavortown.hackclub.com/rails/active_storage/representations/proxy/eyJfcmFpbHMiOnsiZGF0YSI6MTY2NCwicHVyIjoiYmxvYl9pZCJ9fQ==--f45a32bef856a14dcc83229efddfc2723f068f8f/eyJfcmFpbHMiOnsiZGF0YSI6eyJmb3JtYXQiOiJ3ZWJwIiwicmVzaXplX3RvX2xpbWl0IjpbMzYwLG51bGxdLCJzYXZlciI6eyJzdHJpcCI6dHJ1ZSwicXVhbGl0eSI6NzV9fSwicHVyIjoidmFyaWF0aW9uIn19--d6a39ad4705dc76c8821affe402d334558212c92/ai.png",
      "domain_grant.png" => "https://flavortown.hackclub.com/rails/active_storage/representations/proxy/eyJfcmFpbHMiOnsiZGF0YSI6MjI2LCJwdXIiOiJibG9iX2lkIn19--4e4fc0680ac4b0162f01b1b6706d924957b2bfab/eyJfcmFpbHMiOnsiZGF0YSI6eyJmb3JtYXQiOiJ3ZWJwIiwicmVzaXplX3RvX2xpbWl0IjpbMzYwLG51bGxdLCJzYXZlciI6eyJzdHJpcCI6dHJ1ZSwicXVhbGl0eSI6NzV9fSwicHVyIjoidmFyaWF0aW9uIn19--d6a39ad4705dc76c8821affe402d334558212c92/Screenshot%202025-12-10%20at%2002.29.41.png",
      "pcb_credits.png" => "https://flavortown.hackclub.com/rails/active_storage/representations/proxy/eyJfcmFpbHMiOnsiZGF0YSI6MTY4MiwicHVyIjoiYmxvYl9pZCJ9fQ==--aa8f8efd6378b9db1f62fc0130b9de3654a1ec5e/eyJfcmFpbHMiOnsiZGF0YSI6eyJmb3JtYXQiOiJ3ZWJwIiwicmVzaXplX3RvX2xpbWl0IjpbMzYwLG51bGxdLCJzYXZlciI6eyJzdHJpcCI6dHJ1ZSwicXVhbGl0eSI6NzV9fSwicHVyIjoidmFyaWF0aW9uIn19--d6a39ad4705dc76c8821affe402d334558212c92/card_grant_pcb.png",
      "pinecil.png" => "https://flavortown.hackclub.com/rails/active_storage/representations/proxy/eyJfcmFpbHMiOnsiZGF0YSI6MjQwLCJwdXIiOiJibG9iX2lkIn19--fc0fcb1a6e458a05272d6b45042f958db81d70ff/eyJfcmFpbHMiOnsiZGF0YSI6eyJmb3JtYXQiOiJ3ZWJwIiwicmVzaXplX3RvX2xpbWl0IjpbMzYwLG51bGxdLCJzYXZlciI6eyJzdHJpcCI6dHJ1ZSwicXVhbGl0eSI6NzV9fSwicHVyIjoidmFyaWF0aW9uIn19--d6a39ad4705dc76c8821affe402d334558212c92/pinecil.png",
      "mac_mini.png" => "https://flavortown.hackclub.com/rails/active_storage/representations/proxy/eyJfcmFpbHMiOnsiZGF0YSI6MjU2LCJwdXIiOiJibG9iX2lkIn19--29cf14bf5dc02cac15750d150481a7ad562dedd7/eyJfcmFpbHMiOnsiZGF0YSI6eyJmb3JtYXQiOiJ3ZWJwIiwicmVzaXplX3RvX2xpbWl0IjpbMzYwLG51bGxdLCJzYXZlciI6eyJzdHJpcCI6dHJ1ZSwicXVhbGl0eSI6NzV9fSwicHVyIjoidmFyaWF0aW9uIn19--d6a39ad4705dc76c8821affe402d334558212c92/macmini%20Background%20Removed.png",
      "framework_laptop_12.png" => "https://flavortown.hackclub.com/rails/active_storage/representations/proxy/eyJfcmFpbHMiOnsiZGF0YSI6MTQzNSwicHVyIjoiYmxvYl9pZCJ9fQ==--abc9aa0c2868fd1e8a076b5efaa0b9fefc9bc6a0/eyJfcmFpbHMiOnsiZGF0YSI6eyJmb3JtYXQiOiJ3ZWJwIiwicmVzaXplX3RvX2xpbWl0IjpbMzYwLG51bGxdLCJzYXZlciI6eyJzdHJpcCI6dHJ1ZSwicXVhbGl0eSI6NzV9fSwicHVyIjoidmFyaWF0aW9uIn19--d6a39ad4705dc76c8821affe402d334558212c92/fw12.png",
      "raspberry_pi_5.png" => "https://flavortown.hackclub.com/rails/active_storage/representations/proxy/eyJfcmFpbHMiOnsiZGF0YSI6MjEwLCJwdXIiOiJibG9iX2lkIn19--bb4ab60784a2590933a9f7f273851b7c63f2b731/eyJfcmFpbHMiOnsiZGF0YSI6eyJmb3JtYXQiOiJ3ZWJwIiwicmVzaXplX3RvX2xpbWl0IjpbMzYwLG51bGxdLCJzYXZlciI6eyJzdHJpcCI6dHJ1ZSwicXVhbGl0eSI6NzV9fSwicHVyIjoidmFyaWF0aW9uIn19--d6a39ad4705dc76c8821affe402d334558212c92/raspberry-pi-5-raspberry-pi-40958498898115_1000x%20Background%20Removed.png",
      "yubikey.png" => "https://flavortown.hackclub.com/rails/active_storage/representations/proxy/eyJfcmFpbHMiOnsiZGF0YSI6MzQ0LCJwdXIiOiJibG9iX2lkIn19--668918610996dc1c8b30ff0f3c537bec337c697e/eyJfcmFpbHMiOnsiZGF0YSI6eyJmb3JtYXQiOiJ3ZWJwIiwicmVzaXplX3RvX2xpbWl0IjpbMzYwLG51bGxdLCJzYXZlciI6eyJzdHJpcCI6dHJ1ZSwicXVhbGl0eSI6NzV9fSwicHVyIjoidmFyaWF0aW9uIn19--d6a39ad4705dc76c8821affe402d334558212c92/yubikey.png",
      "github_notebook.png" => "https://flavortown.hackclub.com/rails/active_storage/representations/proxy/eyJfcmFpbHMiOnsiZGF0YSI6NjA5OCwicHVyIjoiYmxvYl9pZCJ9fQ==--34eb99b0115ea744c1a356a841bf3f94b4afe2c1/eyJfcmFpbHMiOnsiZGF0YSI6eyJmb3JtYXQiOiJ3ZWJwIiwicmVzaXplX3RvX2xpbWl0IjpbMzYwLG51bGxdLCJzYXZlciI6eyJzdHJpcCI6dHJ1ZSwicXVhbGl0eSI6NzV9fSwicHVyIjoidmFyaWF0aW9uIn19--d6a39ad4705dc76c8821affe402d334558212c92/githubnotebook.png",
      "cloud_hosting_credits.png" => "https://flavortown.hackclub.com/rails/active_storage/representations/proxy/eyJfcmFpbHMiOnsiZGF0YSI6MTY5NCwicHVyIjoiYmxvYl9pZCJ9fQ==--539d87abf6686be7dff2270b9ba2ebab4c02a5f0/eyJfcmFpbHMiOnsiZGF0YSI6eyJmb3JtYXQiOiJ3ZWJwIiwicmVzaXplX3RvX2xpbWl0IjpbMzYwLG51bGxdLCJzYXZlciI6eyJzdHJpcCI6dHJ1ZSwicXVhbGl0eSI6NzV9fSwicHVyIjoidmFyaWF0aW9uIn19--d6a39ad4705dc76c8821affe402d334558212c92/hosting.png",
      "ifixit_credits.png" => "https://flavortown.hackclub.com/rails/active_storage/representations/proxy/eyJfcmFpbHMiOnsiZGF0YSI6MTY4OCwicHVyIjoiYmxvYl9pZCJ9fQ==--e2f0dce28de7e1a690221f6a0c28206f28a2c642/eyJfcmFpbHMiOnsiZGF0YSI6eyJmb3JtYXQiOiJ3ZWJwIiwicmVzaXplX3RvX2xpbWl0IjpbMzYwLG51bGxdLCJzYXZlciI6eyJzdHJpcCI6dHJ1ZSwicXVhbGl0eSI6NzV9fSwicHVyIjoidmFyaWF0aW9uIn19--d6a39ad4705dc76c8821affe402d334558212c92/ifixit.png"
    }

    # Use the configured Active Storage service
    storage_service = ActiveStorage::Blob.service

    uploaded_urls = {}

    images.each do |target_filename, source_url|
      puts "Processing #{target_filename}..."

      begin
        puts "  Downloading from #{source_url[0..80]}..."

        response = Faraday.get(source_url)

        if !response.success?
          puts "  ERROR: Failed to download #{target_filename} - Status: #{response.status}"
          next
        end

        # Determine content type
        content_type = response.headers["content-type"] || "image/webp"

        # Upload to storage
        key = "shop/#{target_filename}"
        io = StringIO.new(response.body)

        puts "  Uploading to storage as #{key}"
        storage_service.upload(key, io, content_type: content_type, filename: target_filename)

        # Get public URL
        public_url = if storage_service.respond_to?(:public_url)
          storage_service.public_url(key)
        else
          "#{ENV.fetch('R2_PUBLIC_URL')}/#{key}"
        end
        uploaded_urls[target_filename] = public_url

        puts "  ✓ Uploaded successfully: #{public_url}"
      rescue => e
        puts "  ERROR: Failed to process #{target_filename}: #{e.message}"
        puts "  #{e.backtrace.first(3).join("\n  ")}"
      end
    end

    puts "\n" + "="*80
    puts "UPLOAD SUMMARY"
    puts "="*80
    uploaded_urls.each do |filename, url|
      puts "#{filename}: #{url}"
    end
  end

  desc "Create shop items with R2-hosted images"
  task create_items: :environment do
    # Product data in order of price (as requested)
    products = [
      {
        name: "Pile of Stickers",
        description: "a few hack club stickers :)",
        price_shards: 3,
        category: "Swag",
        image_filename: "pile_of_stickers.png",
        unlimited_stock: true
      },
      {
        name: "Cloudflare Credits",
        description: "from tunnels to storage to proxies the internet's your oyster",
        price_shards: 6,
        category: "Grants",
        image_filename: "cloudflare_credits.png",
        unlimited_stock: true
      },
      {
        name: "AI Credits",
        description: "Credits for your favorite AI providers!",
        price_shards: 6,
        category: "Grants",
        image_filename: "ai_credits.png",
        unlimited_stock: true
      },
      {
        name: "Domain Grant",
        description: "a $10 grant to buy a domain!",
        price_shards: 6,
        category: "Grants",
        image_filename: "domain_grant.png",
        unlimited_stock: true
      },
      {
        name: "Cloud Hosting Credits",
        description: "Credits for your favorite hosting providers!",
        price_shards: 6,
        category: "Grants",
        image_filename: "cloud_hosting_credits.png",
        unlimited_stock: true
      },
      {
        name: "iFixit Credits",
        description: "you fix it? iFixit!",
        price_shards: 6,
        category: "Grants",
        image_filename: "ifixit_credits.png",
        unlimited_stock: true
      },
      {
        name: "PCB Manufacturing Credits",
        description: "i think pcb, therefore i am pcb",
        price_shards: 12,
        category: "Grants",
        image_filename: "pcb_credits.png",
        unlimited_stock: true
      },
      {
        name: "Smolhaj",
        description: "soft and huggable. a true friend :)",
        price_shards: 18,
        category: "Physical Items",
        image_filename: "smolhaj.png",
        stock_quantity: 50,
        unlimited_stock: false
      },
      {
        name: "Pinecil",
        description: "64 whole pines! doesn't remotely activate for missing hcb receipts",
        price_shards: 18,
        category: "Hardware",
        image_filename: "pinecil.png",
        stock_quantity: 25,
        unlimited_stock: false
      },
      {
        name: "GitHub Notebook",
        description: "git commit -m \"writing a note here\"",
        price_shards: 18,
        category: "Swag",
        image_filename: "github_notebook.png",
        stock_quantity: 100,
        unlimited_stock: false
      },
      {
        name: "YubiKey",
        description: "5C NFC variant!",
        price_shards: 30,
        category: "Hardware",
        image_filename: "yubikey.png",
        stock_quantity: 20,
        unlimited_stock: false
      },
      {
        name: "Raspberry Pi 5",
        description: "mm,,, great for hosting all your yummy apps!",
        price_shards: 78,
        category: "Hardware",
        image_filename: "raspberry_pi_5.png",
        stock_quantity: 15,
        unlimited_stock: false
      },
      {
        name: "Mac Mini",
        description: "M4 chip included!",
        price_shards: 360,
        category: "Hardware",
        image_filename: "mac_mini.png",
        stock_quantity: 5,
        unlimited_stock: false
      },
      {
        name: "Framework Laptop 12",
        description: "repairable touch screen laptop! diy edition",
        price_shards: 480,
        category: "Hardware",
        image_filename: "framework_laptop_12.png",
        stock_quantity: 3,
        unlimited_stock: false
      }
    ]

    # Use the configured Active Storage service
    storage_service = ActiveStorage::Blob.service

    puts "Creating shop items..."
    puts "="*80

    products.each do |product_data|
      # Generate a public URL for a pre-uploaded shop image.
      key = "shop/#{product_data[:image_filename]}"
      image_url = if storage_service.respond_to?(:public_url)
        storage_service.public_url(key)
      else
        "#{ENV.fetch('R2_PUBLIC_URL')}/#{key}"
      end

      # Create the shop item
      shop_item = ShopItem.create!(
        name: product_data[:name],
        description: product_data[:description],
        price_shards: product_data[:price_shards],
        category: product_data[:category],
        image_url: image_url,
        stock_quantity: product_data[:stock_quantity],
        unlimited_stock: product_data[:unlimited_stock],
        active: true
      )

      puts "✓ Created: #{shop_item.name} (#{shop_item.price_shards} shards)"
    end

    puts "="*80
    puts "Created #{products.count} shop items successfully!"
  end

  desc "Remove placeholder shop items"
  task remove_placeholders: :environment do
    puts "Removing placeholder shop items..."

    # Remove all existing shop items (assuming they're all placeholders)
    count = ShopItem.count
    ShopItem.destroy_all

    puts "Removed #{count} shop items."
  end

  desc "Sync shop items to remote database"
  task sync_to_remote: :environment do
    # Get remote database URL from environment variable
    remote_db_url = ENV.fetch("REMOTE_DATABASE_URL") do
      raise "REMOTE_DATABASE_URL environment variable not set. Please set it to sync to remote database."
    end

    puts "Connecting to remote database..."

    # Save local connection config
    local_config = ActiveRecord::Base.connection_db_config

    # Get all shop items from local database first
    local_items = ShopItem.all.map do |item|
      {
        name: item.name,
        description: item.description,
        price_shards: item.price_shards,
        category: item.category,
        image_url: item.image_url,
        stock_quantity: item.stock_quantity,
        unlimited_stock: item.unlimited_stock,
        active: item.active
      }
    end

    # Establish connection to remote database
    ActiveRecord::Base.establish_connection(remote_db_url)
    remote_conn = ActiveRecord::Base.connection

    puts "Syncing #{local_items.count} shop items to remote database..."
    puts "="*80

    local_items.each do |item|
      begin
        # Check if item already exists in remote
        existing = remote_conn.exec_query(
          "SELECT id FROM shop_items WHERE name = $1",
          "SQL",
          [ item[:name] ]
        )

        if existing.any?
          # Update existing item
          remote_conn.exec_query(
            "UPDATE shop_items SET
              description = $1,
              price_shards = $2,
              category = $3,
              image_url = $4,
              stock_quantity = $5,
              unlimited_stock = $6,
              active = $7,
              updated_at = NOW()
            WHERE name = $8",
            "SQL",
            [
              item[:description],
              item[:price_shards],
              item[:category],
              item[:image_url],
              item[:stock_quantity],
              item[:unlimited_stock],
              item[:active],
              item[:name]
            ]
          )
          puts "✓ Updated: #{item[:name]}"
        else
          # Insert new item
          remote_conn.exec_query(
            "INSERT INTO shop_items
              (name, description, price_shards, category, image_url, stock_quantity, unlimited_stock, active, created_at, updated_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW(), NOW())",
            "SQL",
            [
              item[:name],
              item[:description],
              item[:price_shards],
              item[:category],
              item[:image_url],
              item[:stock_quantity],
              item[:unlimited_stock],
              item[:active]
            ]
          )
          puts "✓ Created: #{item[:name]}"
        end
      rescue => e
        puts "ERROR syncing #{item[:name]}: #{e.message}"
        puts "  #{e.backtrace.first(3).join("\n  ")}"
      end
    end

    puts "="*80
    puts "Sync complete!"

    # Restore local connection
    ActiveRecord::Base.establish_connection
  end

  desc "Full setup: remove placeholders, upload images, create items"
  task setup: :environment do
    Rake::Task["shop:remove_placeholders"].invoke
    Rake::Task["shop:upload_flavortown_images"].invoke
    Rake::Task["shop:create_items"].invoke
  end

  desc "Full setup including remote sync"
  task setup_with_remote: :environment do
    Rake::Task["shop:setup"].invoke
    Rake::Task["shop:sync_to_remote"].invoke
  end
end
