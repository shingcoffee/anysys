# frozen_string_literal: true

# An in-page modal holding its content (e.g. a form) from the first render.
# Place it inside a `modal-dialog` Stimulus controller element whose trigger
# calls `modal-dialog#open`; full-screen on phones, centered from `sm`.
class ModalDialogComponent < ApplicationComponent
  # Header tile per tone: an accent "+" for forms, a red warning for
  # confirmations of destructive actions.
  TONES = {
    accent: { tile: "bg-accent-subtle text-accent", icon: "M12 5v14M5 12h14" },
    danger: { tile: "bg-danger-subtle text-danger", icon: "M12 9v4m0 4h.01M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z" }
  }.freeze
  WIDTHS = { md: "sm:max-w-3xl", sm: "sm:max-w-lg" }.freeze

  attr_reader :id, :title, :description

  def initialize(id:, title:, description: nil, tone: :accent, width: :md)
    @id = id
    @title = title
    @description = description
    @tone = TONES.fetch(tone.to_sym, TONES[:accent])
    @width = WIDTHS.fetch(width.to_sym, WIDTHS[:md])
  end

  def title_id = "#{id}-title"
  def tile_class = @tone[:tile]
  def icon_path = @tone[:icon]
  def width_class = @width
end
