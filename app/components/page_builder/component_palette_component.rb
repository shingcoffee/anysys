# frozen_string_literal: true

module PageBuilder
  # Icon-only palette of insertable layout components, rendered inline in the
  # page-builder top toolbar. All interaction is wired to the surrounding
  # `page-builder` Stimulus controller via data-action / data-page-builder-target
  # hooks, so this component holds presentation only.
  class ComponentPaletteComponent < ViewComponent::Base
  end
end
