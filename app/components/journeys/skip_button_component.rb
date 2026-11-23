# frozen_string_literal: true

module Journeys
  # Submits a journey step's form with `_intent=skip` so Advance can pass it
  # without a record. `formnovalidate` lets the skip through required fields.
  class SkipButtonComponent < ApplicationComponent
  end
end
