# frozen_string_literal: true

module PageBuilder
  # All type-specific field-configuration sections shown inside the Validation
  # tab of the property editor: text constraints, textarea options, password
  # options, selection enhancements, switch labels, numeric constraints,
  # currency, rating, date/time constraints, contact, rich text, signature,
  # file/image, and color settings.  Every element is purely static markup
  # wired to the `page-builder` Stimulus controller via `data-type-setting`,
  # `data-page-builder-target`, and `data-action` attributes — no instance
  # state is required.
  class FieldTypeSettingsComponent < ApplicationComponent
  end
end
