# frozen_string_literal: true

module Pages
  # Maps a User-Agent string to a coarse device class used by flowchart
  # runtime config (mobile / tablet / desktop).
  class DeviceType
    def self.call(user_agent)
      return "desktop" if user_agent.blank?

      ua = user_agent.to_s
      if ua.match?(/Tablet|iPad/i)
        "tablet"
      elsif ua.match?(/Mobile|Android|iPhone/i)
        "mobile"
      else
        "desktop"
      end
    end
  end
end
