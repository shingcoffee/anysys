# frozen_string_literal: true

module Admin
  module Entities
    # Body of the full-page entry detail view: one record sheet holding every
    # attribute group (styled with the group's icon and color), then one card
    # per association (Entities::EntryAssociations::Section), beside a sidebar holding the
    # Account card (person entities), record metadata, and, when there are
    # several cards, a section index. On small screens the Account card leads
    # and the record metadata follows the field cards.
    class EntryDetailComponent < ApplicationComponent
      attr_reader :entity, :entry, :display, :associations

      # +writable+ offers add / edit / delete on the association cards.
      # +reveal_section+ names a section id to scroll into view on load.
      # +journey_starts+ (Journeys::RecordStarts) lets a card's "+ Add" start
      # the journey that adds that association's rows for this record.
      def initialize(entity:, entry:, display:, associations: [], writable: false, reveal_section: nil, journey_starts: nil)
        @entity = entity
        @entry = entry
        @display = display
        @associations = associations
        @writable = writable
        @reveal_section = reveal_section
        @journey_starts = journey_starts
      end

      REVEAL_HIGHLIGHT_CLASSES = "ring-2 ring-accent shadow-lg shadow-accent/20"
      REVEAL_CUE_CLASSES = "ring-2 ring-accent ring-offset-2 motion-safe:animate-pulse"

      def reveal_data
        return {} unless index_items.any? { |item| item[:id] == @reveal_section }

        { controller: "section-scroll", section_scroll_id_value: @reveal_section,
          section_scroll_highlight_class: REVEAL_HIGHLIGHT_CLASSES, section_scroll_cue_class: REVEAL_CUE_CLASSES }
      end

      def association_section(section)
        AssociationSectionComponent.new(section: section, entity: entity, entry: entry,
                                        customer_id: entry.customer_id, writable: @writable, heading_tag: :h3,
                                        journey: @writable ? @journey_starts&.for_association(section.association)&.journey : nil)
      end

      # Hosts the association cards' Add / Edit forms.
      def association_dialog? = @writable && associations.any?
      def association_dialog = QuickAddDialogComponent.new(depth: 0)

      def person_link? = entity.person?

      def person_link
        PersonLinkComponent.new(entity: entity, entry: entry, user: entry.user, writable: @writable)
      end

      # With an Account card the sidebar is two grid rows beside a main column
      # spanning both, so the card can precede the main column in the DOM
      # while the metadata still follows it.
      def layout_classes
        classes = "grid grid-cols-1 items-start gap-6 lg:grid-cols-[minmax(0,1fr)_17rem] xl:grid-cols-[minmax(0,1fr)_19rem]"
        person_link? ? "#{classes} lg:grid-rows-[auto_1fr]" : classes
      end

      def main_classes
        classes = "flex min-w-0 flex-col gap-6"
        person_link? ? "#{classes} lg:col-start-1 lg:row-span-2 lg:row-start-1" : classes
      end

      def aside_classes
        classes = "flex min-w-0 flex-col gap-6 lg:sticky lg:top-6 lg:max-h-[calc(100dvh-3rem)] lg:overflow-y-auto"
        person_link? ? "#{classes} lg:col-start-2 lg:row-start-2" : classes
      end

      # Sidebar index entries: attribute groups, then associations.
      def index_items
        sections.map { |section| index_item(section[:id], section[:heading], section[:color], section[:fields].size) } +
          associations.map do |section|
            association = section.association
            index_item(AssociationSectionComponent.section_id(association), association.label,
                       EntityGlyph.color(association.target), section.rows.size)
          end
      end

      def section_index = Admin::SectionIndexComponent.new(items: index_items, id_prefix: "entry")

      # Groups with at least one displayable attribute, in authored order.
      def sections
        @sections ||= entity.grouped_property_schema.filter_map.with_index do |section, index|
          fields = Array(section[:attributes]).select { |field| field["name_slug"].present? }
          next if fields.empty?

          group = section[:group] || {}
          {
            id: "entry-section-#{index + 1}",
            heading: group_heading(section[:group]),
            icon: group["icon"],
            color: group["color"],
            fields: fields
          }
        end
      end

      def section_index? = index_items.size > 1

      def group_heading(group)
        return t("admin_misc.entities.entry_detail.ungrouped") if group.nil?

        group["name"].presence || group["label"].presence || t("admin_misc.entities.entry_detail.ungrouped")
      end

      def group_card(section)
        AttributeGroupCardComponent.new(**section.slice(:id, :heading, :icon, :color, :fields),
                                        entry: entry, display: display, framed: false)
      end

      def system_meta
        [
          { label: t("admin_misc.entities.columns.id"), value: "##{entry.id}", numeric: true },
          { label: t("admin_misc.entities.entry_detail.entity"), value: entity.display_label },
          { label: t("admin_misc.entities.columns.created_at"), time: entry.created_at },
          { label: t("admin_misc.entities.columns.updated_at"), time: entry.updated_at }
        ]
      end

      def timestamp(value)
        return tag.span(blank_display, class: "text-text-tertiary") if value.blank?

        tag.time(helpers.format_datetime(value), datetime: value.iso8601)
      end

      private

      def index_item(id, label, color, count)
        { id: id, label: label, dot: helpers.attribute_group_color_classes(color, variant: :bar), count: count }
      end

      def blank_display
        t("common.labels.em_dash")
      end
    end
  end
end
