# frozen_string_literal: true

namespace :poster_quota do
  desc "Grant bonus paid poster quota to a user by email or Slack ID"
  task :grant, [ :identifier, :amount ] => :environment do |_t, args|
    if args[:identifier].blank? || args[:amount].blank?
      puts "Usage: rails poster_quota:grant[user@email.com,10]"
      puts "   or: rails poster_quota:grant[U092CHMLB24,10]"
      exit 1
    end

    user = User.find_by(email: args[:identifier].downcase) || User.find_by(slack_id: args[:identifier])

    unless user
      puts "❌ User not found: #{args[:identifier]}"
      exit 1
    end

    amount = args[:amount].to_i
    old_bonus = user.bonus_paid_posters || 0
    new_bonus = old_bonus + amount

    user.update!(bonus_paid_posters: new_bonus)

    puts "✅ Granted #{amount} bonus paid posters to #{user.display_name} (#{user.email})"
    puts "   Old bonus: #{old_bonus}"
    puts "   New bonus: #{new_bonus}"
    puts "   New weekly limit: #{user.weekly_paid_poster_limit}"
  end

  desc "Set absolute bonus paid poster quota for a user"
  task :set, [ :identifier, :amount ] => :environment do |_t, args|
    if args[:identifier].blank? || args[:amount].blank?
      puts "Usage: rails poster_quota:set[user@email.com,50]"
      puts "   or: rails poster_quota:set[U092CHMLB24,50]"
      exit 1
    end

    user = User.find_by(email: args[:identifier].downcase) || User.find_by(slack_id: args[:identifier])

    unless user
      puts "❌ User not found: #{args[:identifier]}"
      exit 1
    end

    amount = args[:amount].to_i
    old_bonus = user.bonus_paid_posters || 0

    user.update!(bonus_paid_posters: amount)

    puts "✅ Set bonus paid posters to #{amount} for #{user.display_name} (#{user.email})"
    puts "   Old bonus: #{old_bonus}"
    puts "   New bonus: #{amount}"
    puts "   New weekly limit: #{user.weekly_paid_poster_limit}"
  end

  desc "Show poster quota info for a user"
  task :show, [ :identifier ] => :environment do |_t, args|
    if args[:identifier].blank?
      puts "Usage: rails poster_quota:show[user@email.com]"
      puts "   or: rails poster_quota:show[U092CHMLB24]"
      exit 1
    end

    user = User.find_by(email: args[:identifier].downcase) || User.find_by(slack_id: args[:identifier])

    unless user
      puts "❌ User not found: #{args[:identifier]}"
      exit 1
    end

    puts "📊 Poster Quota for #{user.display_name} (#{user.email})"
    puts "   Base weekly limit: #{User::BASE_WEEKLY_PAID_POSTERS}"
    puts "   Completed referrals this week: #{user.completed_referrals_this_week}"
    puts "   Referral bonus: +#{user.completed_referrals_this_week * User::PAID_POSTER_BONUS_PER_REFERRAL}"
    puts "   Admin bonus: +#{user.bonus_paid_posters || 0}"
    puts "   ─────────────────────────"
    puts "   Total weekly limit: #{user.weekly_paid_poster_limit}"
    puts "   Posters created this week: #{user.posters_created_this_week}"
    puts "   Remaining paid posters: #{user.remaining_paid_posters_this_week}"
  end

  desc "Bulk grant bonus quota to multiple users from file"
  task :bulk_grant, [ :file_path, :amount ] => :environment do |_t, args|
    if args[:file_path].blank? || args[:amount].blank?
      puts "Usage: rails poster_quota:bulk_grant[users.txt,10]"
      puts "   users.txt should contain one email or Slack ID per line"
      exit 1
    end

    unless File.exist?(args[:file_path])
      puts "❌ File not found: #{args[:file_path]}"
      exit 1
    end

    amount = args[:amount].to_i
    success = 0
    failed = 0

    File.readlines(args[:file_path]).each do |line|
      identifier = line.strip
      next if identifier.blank? || identifier.start_with?("#")

      user = User.find_by(email: identifier.downcase) || User.find_by(slack_id: identifier)

      if user
        old_bonus = user.bonus_paid_posters || 0
        user.update!(bonus_paid_posters: old_bonus + amount)
        puts "✅ Granted #{amount} to #{user.display_name} (#{user.email})"
        success += 1
      else
        puts "❌ Not found: #{identifier}"
        failed += 1
      end
    end

    puts "\n📊 Summary: #{success} granted, #{failed} failed"
  end
end
