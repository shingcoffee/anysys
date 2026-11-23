# frozen_string_literal: true

# For controllers whose actions render a ViewComponent straight from the
# controller as a full page.
#
# A Turbo form submission that redirects here asks for turbo-stream first, and
# a component has no template format to fall back on, so Rails would skip the
# HTML layout and serve the page as an empty turbo-stream that Turbo silently
# drops. These pages are always full HTML documents.
module ComponentPageRendering
  extend ActiveSupport::Concern

  included do
    before_action :render_component_page_as_html
  end

  private

  def render_component_page_as_html
    return if request.format.json?

    request.format = :html
  end
end
