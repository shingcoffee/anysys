# frozen_string_literal: true

module PageChromeHelper
  include ThemeResolver

  def page_chrome_theme(page)
    page&.configuration_json&.dig("theme") || {}
  end

  def page_chrome_bg(page)           = resolve_page_chrome_bg(page_chrome_theme(page))
  def page_chrome_form_width(page)   = resolve_form_width(page_chrome_theme(page))
  def page_chrome_header_color(page) = resolve_page_chrome_header_color(page_chrome_theme(page))
  def page_chrome_desc_color(page)   = resolve_page_chrome_desc_color(page_chrome_theme(page))
  def page_chrome_card(page)         = resolve_page_chrome_card(page_chrome_theme(page))
end
