# frozen_string_literal: true

module Websites
  class FooterComponent < PublicComponent
    def initialize(website:, theme: nil)
      @website = website
      @theme = theme || Websites::Theme.new(website.try(:theme))
      @customer_id = website.try(:customer_id)
    end

    attr_reader :website

    def site_name
      website.try(:name).to_s
    end

    def blurb
      footer_data["blurb"].to_s
    end

    def tagline
      website.try(:tagline).to_s
    end

    def columns
      Array(footer_data["columns"]).map { |column| stringify(column) }.select do |column|
        present_text?(column["heading"]) || links_for(column).any?
      end
    end

    def links_for(column)
      Array(column["links"]).map { |link| stringify(link) }.select do |link|
        present_text?(link["label"]) && href_for(link["url"]).present?
      end
    end

    def show_columns?
      columns.any?
    end

    private

    def footer_data
      stringify(website.try(:footer))
    end
  end
end
