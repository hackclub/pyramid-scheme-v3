namespace :referrals do
  desc "Delete orphaned referrals removed from Airtable"
  task delete_orphaned: :environment do
    emails_to_delete = [
      "john@gmail.com",
      "jacob@gmail.com",
      "gmail@gmail.com",
      "johnappleseed@gmail.com"
    ]

    puts "🔍 Finding referrals to delete..."

    referrals = Referral.where(referred_identifier: emails_to_delete)

    if referrals.empty?
      puts "✅ No referrals found with those emails"
      exit
    end

    puts "\n📋 Found #{referrals.count} referrals:"
    referrals.each do |r|
      puts "  - Referrer: #{r.referrer.display_name}, Referred: #{r.referred_identifier}, Status: #{r.status}, Type: #{r.referral_type}"
    end

    puts "\n⚠️  Are you sure you want to delete these referrals? (yes/no)"
    confirmation = STDIN.gets.chomp

    unless confirmation.downcase == "yes"
      puts "❌ Aborted"
      exit
    end

    puts "\n🗑️  Deleting referrals..."

    referrals.each do |referral|
      referrer = referral.referrer
      campaign = referral.campaign
      was_completed = referral.completed?

      # If completed, deduct shards from referrer
      if was_completed && referrer && campaign
        shards_to_deduct = campaign.referral_shards
        actual_deduction = [ shards_to_deduct, referrer.total_shards ].min

        if actual_deduction > 0
          referrer.credit_shards!(
            -actual_deduction,
            transaction_type: "admin_debit",
            transactable: nil,
            description: "Referral deleted (orphaned from Airtable) - #{referral.referred_identifier}"
          )
          puts "  ✓ Deducted #{actual_deduction} shards from #{referrer.display_name}"
        end
      end

      # Delete the referral
      email = referral.referred_identifier
      referral.destroy!
      puts "  ✓ Deleted referral for #{email}"

      # Update referrer's referral count
      if referrer
        referrer.update!(referral_count: referrer.referrals_given.completed.count)
      end
    end

    # Also delete matching AirtableReferral records if they exist
    airtable_refs = AirtableReferral.where("LOWER(email) IN (?)", emails_to_delete.map(&:downcase))
    if airtable_refs.any?
      puts "\n🗑️  Deleting #{airtable_refs.count} matching AirtableReferral records..."
      airtable_refs.destroy_all
      puts "  ✓ Deleted AirtableReferral records"
    end

    puts "\n✅ Cleanup complete! Deleted #{referrals.count} referrals."
  end
end
