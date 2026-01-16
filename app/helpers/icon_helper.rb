# Helper for rendering Lucide icons in views.
#
# Provides a simplified interface to the lucide-rails gem with
# sensible defaults and error handling.
module IconHelper
  # Default icon size in pixels
  DEFAULT_ICON_SIZE = 20
  # Default stroke width for icon lines
  DEFAULT_STROKE_WIDTH = 2

  # Renders a Lucide icon.
  #
  # @param name [String, Symbol] The icon name (underscores converted to hyphens)
  # @param size [Integer] The icon size in pixels
  # @param class_name [String] Additional CSS classes
  # @param stroke_width [Integer] The stroke width for icon lines
  # @return [String] The rendered SVG icon HTML, or empty string on error
  # @example
  #   icon(:arrow_right) # => <svg ...>...</svg>
  #   icon("check", size: 16, class_name: "text-green-500")
  def icon(name, size: DEFAULT_ICON_SIZE, class_name: "", stroke_width: DEFAULT_STROKE_WIDTH)
    lucide_icon(
      name.to_s.tr("_", "-"),
      size: size,
      stroke_width: stroke_width,
      class: class_name.presence
    )
  rescue StandardError
    ""
  end
end
