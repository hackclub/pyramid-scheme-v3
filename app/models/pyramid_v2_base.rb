# frozen_string_literal: true

class PyramidV2Base < ApplicationRecord
  self.abstract_class = true
  connects_to database: { writing: :pyramid_v2, reading: :pyramid_v2 }
end
