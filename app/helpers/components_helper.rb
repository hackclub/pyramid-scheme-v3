require "tailwind_merge"

# Provides shared component styling constants and utilities.
#
# This module defines reusable Tailwind CSS class sets for common
# component variants (primary, secondary, outline, etc.) and a
# utility method for merging Tailwind classes.
#
# @example Merge Tailwind classes
#   tw("px-4 py-2", "px-6") # => "py-2 px-6"
module ComponentsHelper
  # Merges multiple Tailwind CSS class strings, resolving conflicts.
  #
  # @param classes [Array<String>] CSS class strings to merge
  # @return [String] Merged class string with conflicts resolved
  def tw(*classes)
    TailwindMerge::Merger.new.merge(classes.join(" "))
  end

  # @!group Variant Class Constants

  # Primary button/badge styling classes
  PRIMARY_CLASSES = " bg-primary text-primary-foreground hover:bg-primary/80 "
  # Secondary button/badge styling classes
  SECONDARY_CLASSES = " bg-secondary text-secondary-foreground hover:bg-secondary/80 "
  # Outline button/badge styling classes
  OUTLINE_CLASSES = "  border border-input bg-background hover:bg-accent hover:text-accent-foreground "
  # Ghost button/badge styling classes
  GHOST_CLASSES = " hover:bg-accent hover:text-accent-foreground  "
  # Destructive/danger button/badge styling classes
  DESTRUCTIVE_CLASSES = " bg-destructive text-destructive-foreground hover:bg-destructive/90 "

  # @!endgroup

  module Button
    PRIMARY = ComponentsHelper::PRIMARY_CLASSES
    SECONDARY = ComponentsHelper::SECONDARY_CLASSES
    OUTLINE = ComponentsHelper::OUTLINE_CLASSES
    GHOST = ComponentsHelper::GHOST_CLASSES
    DESTRUCTIVE = ComponentsHelper::DESTRUCTIVE_CLASSES
  end
end
