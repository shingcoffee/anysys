# frozen_string_literal: true

class PropertyEditor::EmptyStateComponent < ApplicationComponent
  ICONS = {
    "plus" => '<svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5"><path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" /></svg>',
    "search" => '<svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5"><path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" /></svg>'
  }.freeze

  def initialize(message:, icon: nil)
    @message = message
    @icon = icon
  end

  def icon_svg
    ICONS[@icon]
  end
end
