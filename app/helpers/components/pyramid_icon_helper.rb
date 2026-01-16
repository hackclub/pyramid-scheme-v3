module Components::PyramidIconHelper
  # Renders a Christmas-themed pyramid icon using Lucide pyramid with festive colors
  # size: icon size in pixels
  def christmas_pyramid_icon(size: 40, class_name: "")
    image_tag(
      "/logo.png",
      width: size,
      height: size,
      alt: "Pyramid Scheme",
      class: "inline-block #{class_name}".strip,
      loading: "eager",
      decoding: "async"
    )
  end
end
