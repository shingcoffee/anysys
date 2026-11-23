# frozen_string_literal: true

module Pages
  # Display-only values an entry page starts from when it edits +entry+: the
  # stored value of every primary field the page shows the audience, keyed
  # by slug. Each shown field has a key, blank values included, so a blank
  # stays blank instead of falling back to the entity's default.
  class EntryPrefill
    SECONDARY_SOURCES = %w[base_model bridge identity].freeze

    def self.values(page:, entry:, audience:)
      new(page: page, entry: entry, audience: audience).values
    end

    def initialize(page:, entry:, audience:)
      @page = page
      @entry = entry
      @boundary = FormParams.new(page: page, entity: page.entity, params: {}, audience: audience)
    end

    def values
      data = @entry.data_json || {}
      Page.input_fields_in(@page.configuration_json).each_with_object({}) do |field, values|
        next if SECONDARY_SOURCES.include?(field["source"]) || !@boundary.visible_field?(field)

        slug = (field["property_slug"] || field["id"]).to_s
        values[slug] = @boundary.file_attribute(field) ? @entry.stored_attachments(slug).map { |file| file.filename.to_s } : data[slug]
      end
    end
  end
end
