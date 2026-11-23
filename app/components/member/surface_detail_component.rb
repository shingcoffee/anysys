# frozen_string_literal: true

module Member
  # High-level composer: renders a surface's detail page.
  class SurfaceDetailComponent < ApplicationComponent
    include UsesSiteChrome
    def initialize(surface:, record:, customer:)
      @surface  = surface
      @record   = record
      @customer = customer
    end

    attr_reader :surface, :record, :customer

    def title    = surface.detail.title.call(record)
    def subtitle = surface.detail.subtitle&.call(record)
    def meta     = surface.detail.meta&.call(record)

    def eyebrow
      { label: I18n.t("member.surface_detail.back_to", label: surface.label), path: "/#{customer.id}/member/#{surface.key}" }
    end

    def visible_sections
      surface.detail.sections.reject { |s| s[:when] && !s[:when].call(record) }
    end

    def grid_section?(section) = section[:rows].present?
    def list_section?(section) = section[:list].present?

    def list_items(section) = section[:list].call(record)

    def render_left(item)  = ERB::Util.html_escape(item[:left].to_s)
    def render_right(item) = Member::Formatters.format(item[:right], item[:format] || :string)
  end
end
