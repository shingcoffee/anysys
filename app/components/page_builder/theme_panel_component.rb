# frozen_string_literal: true

module PageBuilder
  # Body of the "Form Theme" config modal in the page builder: presets, colors,
  # typography, layout, input, and submit-button controls. All options are
  # static literals wired to the `page-builder` Stimulus controller via
  # `data-action`/`data-theme-*` attributes — no instance state required.
  class ThemePanelComponent < ApplicationComponent
  end
end
