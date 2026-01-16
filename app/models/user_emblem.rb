# frozen_string_literal: true

class UserEmblem < ApplicationRecord
  belongs_to :user, inverse_of: :user_emblems
  belongs_to :campaign, inverse_of: :user_emblems

  EMBLEM_TYPES = %w[participant top_referrer top_poster early_bird].freeze

  validates :emblem_type, presence: true, inclusion: { in: EMBLEM_TYPES }
  validates :earned_at, presence: true
  validates :user_id, uniqueness: { scope: [ :campaign_id, :emblem_type ] }

  scope :for_campaign, ->(campaign) { where(campaign: campaign) }
  scope :by_type, ->(type) { where(emblem_type: type) }
  scope :recent, -> { order(earned_at: :desc) }
  scope :with_user, -> { includes(:user) }
  scope :with_campaign, -> { includes(:campaign) }

  def emblem_name
    case emblem_type
    when "participant"
      "#{campaign.name} Participant"
    when "top_referrer"
      "#{campaign.name} Top Referrer"
    when "top_poster"
      "#{campaign.name} Top Poster"
    when "early_bird"
      "#{campaign.name} Early Bird"
    else
      emblem_type.titleize
    end
  end

  def emblem_icon
    case emblem_type
    when "participant"
      "trophy"
    when "top_referrer"
      "users"
    when "top_poster"
      "image"
    when "early_bird"
      "zap"
    else
      "award"
    end
  end
end
