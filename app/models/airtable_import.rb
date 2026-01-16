# frozen_string_literal: true

class AirtableImport < ApplicationRecord
  belongs_to :importable, polymorphic: true

  validates :table_name, presence: true
  validates :airtable_record_id, presence: true
  validates :airtable_record_id, uniqueness: { scope: :table_name }

  scope :for_table, ->(table_name) { where(table_name: table_name) }
  scope :recently_imported, -> { order(last_imported_at: :desc) }
  scope :oldest_imported, -> { order(Arel.sql("last_imported_at ASC NULLS FIRST")) }

  def mark_imported!
    update!(last_imported_at: Time.current)
  end

  def self.already_imported?(table_name, airtable_record_id)
    exists?(table_name: table_name, airtable_record_id: airtable_record_id)
  end

  def self.find_or_initialize_for(table_name, airtable_record_id, importable)
    find_or_initialize_by(
      table_name: table_name,
      airtable_record_id: airtable_record_id
    ) do |import|
      import.importable = importable
    end
  end
end
