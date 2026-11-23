# frozen_string_literal: true

# Direction glyph for the sidebar collapse control: double chevrons point the
# way the sidebar will move — left (collapse) while it is open, right (expand)
# while it is an icon rail.
class SidebarToggleIconComponent < ApplicationComponent
  def initialize(expanded:)
    @expanded = expanded
  end

  def expanded?
    @expanded
  end
end
