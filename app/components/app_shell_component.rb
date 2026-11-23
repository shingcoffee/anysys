# frozen_string_literal: true

# Generic top-level chrome for pages rendered through the `application` layout —
# i.e. surfaces with no tenant dashboard: the email-unsubscribe confirmation,
# error pages, and any other anonymous/public fallback.
#
# Deliberately brand-only: it carries NO dashboard navigation. The old header
# linked to Flowcharts / Code Generators, which are platform-owner maintenance
# tools requiring a tenant (:customer_id) and elevated access — destinations
# that are dead or forbidden in this layout's no-tenant context.
class AppShellComponent < ApplicationComponent
  def initialize(home_path: nil)
    @home_path = home_path
  end

  def brand_href
    @home_path || helpers.root_path
  end

  def flash_messages
    helpers.flash
  end

  # Visual treatment per flash type: ring/text/bg classes + an outline icon path.
  def flash_style(type)
    if %w[alert error].include?(type.to_s)
      { classes: "bg-danger-subtle text-danger ring-danger/20",
        icon: "M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z" }
    else
      { classes: "bg-success-subtle text-success ring-success/20",
        icon: "M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0z" }
    end
  end
end
