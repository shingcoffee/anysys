# frozen_string_literal: true

class FlowchartInfoCardComponent < ApplicationComponent
  include ActionView::Helpers::TextHelper

  attr_reader :flowchart, :pages

  # +pages+ are the pages bound to the flowchart that the viewer may open.
  def initialize(flowchart:, pages:)
    @flowchart = flowchart
    @pages = pages
  end

  def format_datetime(datetime)
    return "-" if datetime.blank?

    datetime.respond_to?(:strftime) ? I18n.l(datetime, format: :long) : datetime.to_s
  end

  def page_path(page)
    helpers.admin_maintenance_page_path(effective_customer_id, page)
  end

  # Returns the effective customer_id for URL generation
  # For customer_specific flowcharts: uses the flowchart's customer_id
  # For shared flowcharts: uses the current customer's ID
  def effective_customer_id
    flowchart.customer_id || Current.customer_id
  end
end
