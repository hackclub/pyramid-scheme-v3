namespace :geocode do
  desc "Queue geocoding jobs for users with IP addresses but no geocoding data"
  task users: :environment do
    users = User.where.not(last_ip_address: nil).where(geocoded_at: nil)
    count = users.count

    puts "Found #{count} users to geocode"

    users.find_each do |user|
      GeocodeIpJob.perform_later("User", user.id)
    end

    puts "Queued #{count} geocoding jobs"
  end
end
