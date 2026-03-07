# frozen_string_literal: true

mode = ENV.fetch("MODE", "audit")
apply = ENV["APPLY"] == "1"
period = if ENV["PERIOD_START"].present? && ENV["PERIOD_END"].present?
  ReferralLeaderboardPeriod.new(
    starts_at: Time.zone.parse(ENV.fetch("PERIOD_START")),
    ends_at: Time.zone.parse(ENV.fetch("PERIOD_END"))
  )
else
  ReferralLeaderboardPeriod.previous
end

cashout = ReferralLeaderboardCashoutService.new(period: period, apply: apply)
reconciliation = ReferralRewardReconciliationService.new(apply: apply)

case mode
when "audit"
  puts "Referral leaderboard cashout preview (#{period.payout_label})"
  cashout.call.awards.each { |award| puts award.inspect }
  puts
  puts "Referral reward reconciliation preview"
  reconciliation.call.corrections.each { |correction| puts correction.inspect }
when "cashout"
  puts "Referral leaderboard cashout #{apply ? 'apply' : 'preview'} (#{period.payout_label})"
  cashout.call.awards.each { |award| puts award.inspect }
when "reconcile"
  puts "Referral reward reconciliation #{apply ? 'apply' : 'preview'}"
  reconciliation.call.corrections.each { |correction| puts correction.inspect }
when "all"
  puts "Referral leaderboard cashout #{apply ? 'apply' : 'preview'} (#{period.payout_label})"
  cashout.call.awards.each { |award| puts award.inspect }
  puts
  puts "Referral reward reconciliation #{apply ? 'apply' : 'preview'}"
  reconciliation.call.corrections.each { |correction| puts correction.inspect }
else
  abort "Unknown MODE=#{mode.inspect}. Use audit, cashout, reconcile, or all."
end
