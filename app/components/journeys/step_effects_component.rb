# frozen_string_literal: true

module Journeys
  # A step row's read-only "On submit" block: what its page's processing does
  # and which other journeys pick up the record it leaves behind
  # (BuilderCatalog#effects). Lines that only hold when the step creates its
  # record drop out for a row that edits one (+updating+). Hidden until the
  # row has a page; the builder controller re-fills it from the same payload
  # (EditorComponent#pages_payload) when the page or step type changes.
  class StepEffectsComponent < ApplicationComponent
    def self.payload(catalog, page, path)
      effects = catalog.effects(page)
      {
        "title" => effects.flowchart && I18n.t("journeys.admin.effects.processing", name: effects.flowchart.name),
        "path" => effects.flowchart && path,
        "lines" => effects.lines, "creating" => effects.creating,
        "next" => effects.next, "nextCreating" => effects.next_creating, "skips" => effects.skips
      }
    end

    def initialize(catalog:, page:, updating: false)
      @catalog = catalog
      @page = page
      @updating = updating
    end

    def hidden? = @page.nil?
    def title = data["title"]
    def path = data["path"]
    def lines = data.fetch("lines", []) + (@updating ? [] : data.fetch("creating", []))
    def next_lines = data.fetch("next", []) + (@updating ? [] : data.fetch("nextCreating", []))

    private

    def data
      @data ||= @page ? self.class.payload(@catalog, @page, helpers.admin_maintenance_page_path(@catalog.customer_id, @page)) : {}
    end
  end
end
