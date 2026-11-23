# frozen_string_literal: true

module Admin
  module Entities
    # One association of a primary entry on its detail page: the bridge rows
    # that link the entry to records of the associated entity, each showing the
    # linked record and the bridge's own attributes (e.g. a course and its
    # grade), with add / edit / delete when the primary entity is writable.
    class AssociationSectionComponent < ApplicationComponent
      def self.section_id(association) = "entry-association-#{association.id}"

      attr_reader :section, :entity, :entry, :customer_id

      # +framed+ draws its own card; unframed sections sit inside a card the
      # caller provides. +journey+ is the launched journey that adds this
      # association's rows for the entry; its Add starts that journey instead
      # of opening the dialog.
      def initialize(section:, entity:, entry:, customer_id:, writable:, heading_tag: :h2, framed: true, journey: nil)
        @section = section
        @entity = entity
        @entry = entry
        @customer_id = customer_id
        @writable = writable
        @heading_tag = heading_tag
        @framed = framed
        @journey = journey
      end

      def section_classes
        classes = "scroll-mt-6 transition-shadow duration-500"
        @framed ? "card overflow-hidden #{classes}" : classes
      end

      def writable? = @writable
      def row_actions? = writable?
      def heading_tag = @heading_tag
      def add_label = t("admin_misc.entities.association_entries.add")
      def add_button_class = "min-h-9 shrink-0"
      def association = section.association
      def rows = section.rows
      def columns = association.columns
      def id = self.class.section_id(association)
      def heading = association.label

      def icon_tile_classes
        helpers.attribute_group_color_classes(EntityGlyph.color(association.target), variant: :soft)
      end

      def column_label(column)
        column["display_label"].presence || column["name"].presence || column["name_slug"].to_s
      end

      def cell_text(row, column) = section.display.text(row, column["name_slug"])
      def blank?(text) = text == t("common.labels.em_dash")

      # The linked record's detail page, when the cell is a single reference
      # to a record that still exists.
      def reference_href(row, column)
        return unless association.reference_column?(column)

        value = row.data_json[column["name_slug"]]
        return if value.is_a?(Array) || !section.existing_target_ids.fetch(column["name_slug"].to_s, Set.new).include?(value.to_s)

        helpers.admin_entity_entry_path(customer_id, column.dig("config", "entity_id"), value)
      end

      def title_column = columns.first
      def detail_columns = columns.drop(1)

      def new_path
        helpers.new_admin_entity_entry_association_entry_path(customer_id, entity, entry, association.id)
      end

      def journey_start? = @journey.present?
      def journey_start_path = helpers.admin_entity_entry_journey_path(customer_id, entity, entry, @journey.key)
      def journey_start_title = t("journeys.runtime.start_from_record", name: @journey.name)

      def journey_start_attributes
        ButtonComponent.new(tag: :button, type: "submit", variant: :secondary, size: :sm, class: add_button_class)
                       .html_attributes.merge(title: journey_start_title, data: { section_scroll_target: "cue", journey_start: @journey.key })
      end

      def edit_path(row)
        helpers.edit_admin_entity_entry_association_entry_path(customer_id, entity, entry, association.id, row)
      end

      def destroy_path(row)
        helpers.admin_entity_entry_association_entry_path(customer_id, entity, entry, association.id, row)
      end

      def section_data
        return {} unless writable?

        { controller: "association-dialog",
          association_dialog_entity_quick_add_dialog_outlet: "##{QuickAddDialogComponent.dialog_id(0)}" }
      end

      # Add / Edit open in the dialog; their hrefs stay full pages without it.
      # Turbo reuses a hover-prefetched response for any later GET of the same
      # URL, so a prefetched full page would replace the dialog's frame request
      # and render the page's empty frame.
      # The Add button is what a section-scroll reveal draws attention to.
      def add_button_data = dialog_link_data("new_title").merge(section_scroll_target: "cue")

      def dialog_link_data(title_key)
        { turbo_frame: "_top", turbo_prefetch: false, action: "association-dialog#open",
          association_dialog_title_param: t("admin_misc.entities.association_entries.#{title_key}", name: heading) }
      end

      def row_title(row)
        title_column ? cell_text(row, title_column) : t("admin_misc.entities.entry_detail.title", id: row.id)
      end
    end
  end
end
