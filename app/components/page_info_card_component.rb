# frozen_string_literal: true

class PageInfoCardComponent < ApplicationComponent
  include ActionView::Helpers::TextHelper

  attr_reader :page, :customer_id

  def initialize(page:, customer_id:)
    @page        = page
    @customer_id = customer_id
  end

  def format_datetime(datetime)
    return "-" if datetime.blank?

    datetime.respond_to?(:strftime) ? I18n.l(datetime, format: :long) : datetime.to_s
  end

  def entity_link_path
    helpers.admin_maintenance_entity_path(customer_id, page.entity) if page.entity
  end
end
