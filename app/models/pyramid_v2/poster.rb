# frozen_string_literal: true

module PyramidV2
  class Poster < PyramidV2Base
    self.table_name = "posters"

    # Get image URL from active storage
    def image_url
      return nil unless id.present?

      # Query active storage to get the blob key
      result = self.class.connection.execute(<<~SQL)
        SELECT b.key
        FROM active_storage_attachments a
        JOIN active_storage_blobs b ON a.blob_id = b.id
        WHERE a.record_type = 'Poster'
          AND a.record_id = '#{id}'
          AND a.name = 'image'
        LIMIT 1
      SQL

      return nil if result.ntuples == 0

      key = result.getvalue(0, 0)
      "https://cdn.hackclub.com/#{key}"
    end
  end
end
