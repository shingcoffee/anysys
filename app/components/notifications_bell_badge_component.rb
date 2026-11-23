# frozen_string_literal: true

# Unread-count badge fragment. Always rendered (even when empty) so a
# mark-read turbo_stream can replace it by id.
class NotificationsBellBadgeComponent < ApplicationComponent
  DOM_ID = "notifications-badge"

  def initialize(count:, label:)
    @count = count
    @label = label
  end

  attr_reader :count, :label

  def unread? = count.positive?

  def dom_id = DOM_ID
end
