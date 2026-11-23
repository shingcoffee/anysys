# frozen_string_literal: true

module Member
  # The unified member page template. Every member-facing
  # view must render through this component so that content width
  # is identical across the member surface area. Primary is
  # always lg:col-span-8; the aside column is always reserved
  # (filled or with an invisible placeholder) so single-word pages
  # render at exactly the same width as the home page.
  class PageLayoutComponent < ApplicationComponent
    renders_one :hero
    renders_one :primary
    renders_one :aside
  end
end
