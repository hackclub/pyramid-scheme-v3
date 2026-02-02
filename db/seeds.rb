# frozen_string_literal: true

# Pyramid Scheme Database Seeds
# This file creates the initial data needed to run the application.
# Run with: bin/rails db:seed

puts "🌱 Seeding database..."

# =============================================================================
# CAMPAIGNS
# =============================================================================
puts "\n📢 Creating campaigns..."

campaigns_data = [
  {
    slug: "flavortown",
    name: "Flavortown",
    theme: "flavortown",
    description: "Welcome to Flavortown! Spread the word about Hack Club and earn shards to redeem for awesome swag.",
    active: true,
    status: "open",
    referral_shards: 3,
    poster_shards: 1,
    required_coding_minutes: 60,
    subdomain: "flavortown",
    theme_config: {
      primary_color: "#ff6b35",
      secondary_color: "#ff8c5a",
      background_color: "#1a0f0a"
    }
  },
  {
    slug: "aces",
    name: "Aces",
    theme: "aces",
    description: "The Aces campaign - a new way to spread the word about Hack Club. Coming soon!",
    active: true,
    status: "coming_soon",
    referral_shards: 3,
    poster_shards: 1,
    required_coding_minutes: 60,
    subdomain: "aces",
    theme_config: {
      primary_color: "#ffd700",
      secondary_color: "#840027",
      background_color: "#840027"
    }
  },
  {
    slug: "sleepover",
    name: "Sleepover",
    theme: "sleepover",
    description: "A program for teenage girls to code and earn prizes.",
    active: true,
    status: "open",
    referral_shards: 3,
    poster_shards: 1,
    required_coding_minutes: 60,
    subdomain: "sleepover",
    theme_config: {
      primary_color: "#6c8be1",
      secondary_color: "#dfa2ad",
      background_color: "#d9daf8"
    }
  },
  {
    slug: "construct",
    name: "Construct",
    theme: "construct",
    description: "Build hardware projects and ship them to earn rewards!",
    active: false,
    status: "closed",
    referral_shards: 3,
    poster_shards: 1,
    required_coding_minutes: 1,
    subdomain: "construct",
    theme_config: {
      primary_color: "#00bcd4",
      secondary_color: "#0097a7",
      background_color: "#0d1117"
    }
  },
  {
    slug: "hctg",
    name: "Hack Club: The Game",
    theme: "hctg",
    description: "Build projects, then compete in a scavenger hunt adventure game across Manhattan.",
    active: true,
    status: "open",
    referral_shards: 3,
    poster_shards: 1,
    required_coding_minutes: 60,
    subdomain: "hctg",
    base_url: "https://hctg.hack.club",
    theme_config: {
      primary_color: "#ef4444",
      secondary_color: "#2563eb",
      background_color: "#000000"
    }
  }
]

campaigns_data.each do |attrs|
  campaign = Campaign.find_or_initialize_by(slug: attrs[:slug])
  campaign.assign_attributes(attrs)
  campaign.save!
  puts "  ✓ #{campaign.name} (#{campaign.slug}) - #{campaign.status}"
end

# =============================================================================
# DEVELOPMENT ONLY DATA
# =============================================================================
if Rails.env.development?
  puts "\n🛠️  Creating development-only data..."

  # ---------------------------------------------------------------------------
  # Shop Items
  # ---------------------------------------------------------------------------
  puts "\n🛒 Creating shop items..."

  shop_items_data = [
    {
      name: "Pile of Stickers",
      description: "A few Hack Club stickers :)",
      price_shards: 3,
      unlimited_stock: true,
      category: "Swag",
      active: true,
      image_url: "https://flavortown.hackclub.com/rails/active_storage/representations/proxy/eyJfcmFpbHMiOnsiZGF0YSI6NTMyLCJwdXIiOiJibG9iX2lkIn19--00960983352d912aa3d30bbee91e810628fffb7f/eyJfcmFpbHMiOnsiZGF0YSI6eyJmb3JtYXQiOiJ3ZWJwIiwicmVzaXplX3RvX2xpbWl0IjpbMzYwLG51bGxdLCJzYXZlciI6eyJzdHJpcCI6dHJ1ZSwicXVhbGl0eSI6NzV9fSwicHVyIjoidmFyaWF0aW9uIn19--d6a39ad4705dc76c8821affe402d334558212c92/pile_of_stickers.png"
    },
    {
      name: "Smolhåj",
      description: "Soft and huggable. A true friend :)",
      price_shards: 133,
      unlimited_stock: false,
      stock_quantity: 50,
      category: "Swag",
      active: true,
      image_url: "https://flavortown.hackclub.com/rails/active_storage/representations/proxy/eyJfcmFpbHMiOnsiZGF0YSI6MjM1LCJwdXIiOiJibG9iX2lkIn19--34b25d54db53c692f44b9f67a4c1f6ffd2eb391c/eyJfcmFpbHMiOnsiZGF0YSI6eyJmb3JtYXQiOiJ3ZWJwIiwicmVzaXplX3RvX2xpbWl0IjpbMzYwLG51bGxdLCJzYXZlciI6eyJzdHJpcCI6dHJ1ZSwicXVhbGl0eSI6NzV9fSwicHVyIjoidmFyaWF0aW9uIn19--d6a39ad4705dc76c8821affe402d334558212c92/blahaj.png"
    },
    {
      name: "HackDucky",
      description: "It hacks and it quacks",
      price_shards: 100,
      unlimited_stock: false,
      stock_quantity: 25,
      category: "Swag",
      active: true,
      image_url: "https://flavortown.hackclub.com/rails/active_storage/representations/proxy/eyJfcmFpbHMiOnsiZGF0YSI6MzcxLCJwdXIiOiJibG9iX2lkIn19--92673bfd80d9023376d6529f73f47087787df41c/eyJfcmFpbHMiOnsiZGF0YSI6eyJmb3JtYXQiOiJ3ZWJwIiwicmVzaXplX3RvX2xpbWl0IjpbMzYwLG51bGxdLCJzYXZlciI6eyJzdHJpcCI6dHJ1ZSwicXVhbGl0eSI6NzV9fSwicHVyIjoidmFyaWF0aW9uIn19--d6a39ad4705dc76c8821affe402d334558212c92/image%20(1).png"
    },
    {
      name: "Hack Club T-Shirt",
      description: "Rep Hack Club with this classic tee",
      price_shards: 50,
      unlimited_stock: false,
      stock_quantity: 100,
      category: "Apparel",
      active: true
    },
    {
      name: "MacBook Sticker Pack",
      description: "Premium vinyl stickers for your laptop",
      price_shards: 10,
      unlimited_stock: true,
      category: "Swag",
      active: true
    }
  ]

  # Deactivate items not in the seed list
  ShopItem.where.not(name: shop_items_data.map { |i| i[:name] }).update_all(active: false)

  shop_items_data.each do |attrs|
    item = ShopItem.find_or_initialize_by(name: attrs[:name])
    item.assign_attributes(attrs)
    item.save!
    puts "  ✓ #{item.name} (#{item.price_shards} shards)"
  end

  # ---------------------------------------------------------------------------
  # Test Users
  # ---------------------------------------------------------------------------
  puts "\n👤 Creating test users..."

  test_users_data = [
    {
      email: "admin@hackclub.com",
      display_name: "Test Admin",
      role: :admin,
      slack_id: "U12345ADMIN",
      total_shards: 1000
    },
    {
      email: "fulfiller@hackclub.com",
      display_name: "Test Fulfiller",
      role: :fulfiller,
      slack_id: "U12345FULFILL",
      total_shards: 50
    },
    {
      email: "testuser@hackclub.com",
      display_name: "Test User",
      role: :user,
      slack_id: "U12345USER",
      total_shards: 25
    },
    {
      email: "poster.champion@hackclub.com",
      display_name: "Poster Champion",
      role: :user,
      slack_id: "U12345POSTER",
      total_shards: 150,
      poster_count: 15
    }
  ]

  flavortown = Campaign.find_by!(slug: "flavortown")

  test_users_data.each do |attrs|
    user = User.find_or_initialize_by(email: attrs[:email])
    user.assign_attributes(attrs)
    user.save!
    puts "  ✓ #{user.display_name} (#{user.role}, #{user.total_shards} shards)"

    # Create emblems for active users
    UserEmblem.find_or_create_by!(user: user, campaign: flavortown, emblem_type: "participant") do |e|
      e.earned_at = Time.current
    end
  end

  # ---------------------------------------------------------------------------
  # Test Posters (for testing QR code URLs)
  # ---------------------------------------------------------------------------
  puts "\n📄 Creating test posters..."

  test_user = User.find_by!(email: "testuser@hackclub.com")
  poster_champion = User.find_by!(email: "poster.champion@hackclub.com")

  # Create posters for different campaigns to test URL generation
  Campaign.active.each do |campaign|
    poster = Poster.find_or_initialize_by(
      user: test_user,
      campaign: campaign,
      referral_code: "TEST#{campaign.slug.upcase[0..3]}"
    )

    unless poster.persisted?
      poster.qr_code_token ||= SecureRandom.alphanumeric(12)
      poster.verification_status = "pending"
      poster.poster_type = "color"
      poster.save!
      puts "  ✓ Test poster for #{campaign.name}: #{poster.referral_code}"
    end
  end

  # Create verified posters for poster champion
  3.times do |i|
    poster = Poster.find_or_initialize_by(
      user: poster_champion,
      campaign: flavortown,
      referral_code: "CHAMP#{format('%03d', i + 1)}"
    )

    unless poster.persisted?
      poster.qr_code_token ||= SecureRandom.alphanumeric(12)
      poster.verification_status = "success"
      poster.poster_type = "color"
      poster.verified_at = Time.current - (i + 1).days
      poster.location_description = "Test Location #{i + 1}"
      poster.save!
      puts "  ✓ Verified poster: #{poster.referral_code}"
    end
  end

  # ---------------------------------------------------------------------------
  # Test Referrals
  # ---------------------------------------------------------------------------
  puts "\n🔗 Creating test referrals..."

  admin_user = User.find_by!(email: "admin@hackclub.com")

  referrals_data = [
    { identifier: "referred1@test.com", status: :completed, minutes: 120 },
    { identifier: "referred2@test.com", status: :id_verified, minutes: 30 },
    { identifier: "referred3@test.com", status: :pending, minutes: 0 }
  ]

  referrals_data.each do |ref_attrs|
    referral = Referral.find_or_initialize_by(
      referrer: admin_user,
      campaign: flavortown,
      referred_identifier: ref_attrs[:identifier]
    )

    unless referral.persisted?
      referral.status = ref_attrs[:status]
      referral.tracked_minutes = ref_attrs[:minutes]
      referral.referral_type = "link"
      referral.completed_at = Time.current if ref_attrs[:status] == :completed
      referral.save!
      puts "  ✓ Referral to #{ref_attrs[:identifier]} (#{ref_attrs[:status]})"
    end
  end

  # ---------------------------------------------------------------------------
  # Users with Referral Sources
  # ---------------------------------------------------------------------------
  puts "\n🎯 Creating users with referral sources..."

  ref_sources_data = [
    { email: "twitter1@test.com", display_name: "Twitter User 1", source: "twitter", days_ago: 5 },
    { email: "twitter2@test.com", display_name: "Twitter User 2", source: "twitter", days_ago: 10 },
    { email: "twitter3@test.com", display_name: "Twitter User 3", source: "twitter", days_ago: 15 },
    { email: "twitter4@test.com", display_name: "Twitter User 4", source: "twitter", days_ago: 20 },
    { email: "twitter5@test.com", display_name: "Twitter User 5", source: "twitter", days_ago: 25 },
    { email: "reddit1@test.com", display_name: "Reddit User 1", source: "reddit", days_ago: 3 },
    { email: "reddit2@test.com", display_name: "Reddit User 2", source: "reddit", days_ago: 7 },
    { email: "reddit3@test.com", display_name: "Reddit User 3", source: "reddit", days_ago: 12 },
    { email: "hn1@test.com", display_name: "HN User 1", source: "hackernews", days_ago: 2 },
    { email: "hn2@test.com", display_name: "HN User 2", source: "hackernews", days_ago: 8 },
    { email: "hn3@test.com", display_name: "HN User 3", source: "hackernews", days_ago: 14 },
    { email: "youtube1@test.com", display_name: "YouTube User 1", source: "youtube", days_ago: 1 },
    { email: "youtube2@test.com", display_name: "YouTube User 2", source: "youtube", days_ago: 6 },
    { email: "tiktok1@test.com", display_name: "TikTok User", source: "tiktok", days_ago: 4 },
    { email: "friend1@test.com", display_name: "Friend Referral 1", source: "friend", days_ago: 9 },
    { email: "friend2@test.com", display_name: "Friend Referral 2", source: "friend", days_ago: 11 }
  ]

  ref_sources_data.each do |attrs|
    user = User.find_or_initialize_by(email: attrs[:email])
    user.display_name = attrs[:display_name]
    user.signup_ref_source = attrs[:source]
    user.slack_id = "U#{SecureRandom.hex(4).upcase}"
    user.total_shards = rand(0..50)
    user.poster_count = rand(0..5)
    user.created_at = attrs[:days_ago].days.ago
    user.save!
    puts "  ✓ #{user.display_name} (ref: #{user.signup_ref_source})"
  end

  puts "\n✅ Development seed data created!"
end

puts "\n🎉 Seeding complete!"
puts "   Campaigns: #{Campaign.count}"
puts "   Shop Items: #{ShopItem.count}"
puts "   Users: #{User.count}" if Rails.env.development?
