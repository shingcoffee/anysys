# frozen_string_literal: true

# Bell trigger fragment. Replaced independently by the mark-read turbo
# stream so the notifications-menu Stimulus root stays mounted.
class NotificationsBellTriggerComponent < ApplicationComponent
  DOM_ID = "notifications-trigger"

  def initialize(aria_label:, expanded: false)
    @aria_label = aria_label
    @expanded = expanded
  end

  attr_reader :aria_label

  def expanded? = @expanded

  def dom_id = DOM_ID
end
