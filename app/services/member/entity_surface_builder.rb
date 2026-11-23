# frozen_string_literal: true

module Member
  module EntitySurfaceBuilder
    DEFAULT_POSITION_BASE = 200

    # Formats that print text as-is read display text (option labels,
    # referenced records, derived values); dates and money keep the stored
    # value their formatter expects.
    TEXT_FORMATS = %i[string number].freeze

    def self.call(entity:, customer:)
      grouped     = entity.grouped_property_schema
      owner_slug  = People::Ownership.owner_reference(entity)&.slug
      surface_fields = grouped.flat_map { |s| s[:attributes] }.select { |f| member_surface_field?(f, owner_slug) }

      columns = surface_fields.map { |f|
        slug = f["name_slug"] || f["key"] || ""
        next nil if slug.empty?

        computed = f["type"] == Entity::COMPUTED_TYPE
        format = computed ? :number : format_for(f["type"])
        {
          key:      slug.to_sym,
          label:    f["display_label"].presence || f["name"].presence || slug.to_s,
          value:    TEXT_FORMATS.include?(format) ? display_reader(slug) : data_reader(slug),
          format:   format,
          align:    computed ? :right : align_for(f["type"]),
          hideable: true
        }
      }.compact

      columns = [{ key: :id, label: I18n.t("chrome.labels.id"), value: ->(e) { e.id }, hideable: false }] if columns.empty?

      Member::Surface.new(
        key:   :"entity_#{entity.id}",
        label: entity.display_label,
        icon:  :rectangle_stack,
        default_position: DEFAULT_POSITION_BASE + entity.id.to_i,
        default_enabled: People::Ownership.kind(entity) != :open,
        enabled_for: ->(user) { user&.customer_id == customer.id },
        groups: grouped.map { |s| { group: s[:group], attributes: s[:attributes].select { |f| member_surface_field?(f, owner_slug) } } },
        index: Member::Surface::Index.new(
          title:    entity.display_label,
          subtitle: entity.description.presence || I18n.t("member.entity_surfaces.subtitle"),
          scope:    ->(user) {
            People::Ownership.scope(
              entity, viewer: user, audience: EntityAttributeAudience::MEMBER, customer_id: customer.id
            )
          },
          columns:  columns,
          empty_state: {
            headline: I18n.t("member.entity_surfaces.empty_headline", name: entity.display_label.downcase),
            body:     I18n.t("member.entity_surfaces.empty_body"),
            icon:     :rectangle_stack
          },
          per_page: 20
        ),
        detail: build_detail(entity, columns)
      ).tap(&:validate!)
    end

    def self.build_detail(entity, columns)
      detail = Member::SurfaceTemplateApplier.call(entity: entity) || legacy_detail(columns)
      omit_owner_rows(detail, entity)
    end

    def self.omit_owner_rows(detail, entity)
      slug = People::Ownership.owner_reference(entity)&.slug
      return detail if slug.blank?

      sections = Array(detail.sections).map do |section|
        next section unless section[:rows].is_a?(Array)

        section.merge(rows: section[:rows].reject { |row| row[:key].to_s == slug })
      end
      Member::Surface::Detail.new(
        title: detail.title,
        subtitle: detail.subtitle,
        meta: detail.meta,
        sections: sections
      )
    end

    def self.legacy_detail(columns)
      Member::Surface::Detail.new(
        title:    ->(entry) { "##{entry.id}" },
        subtitle: ->(entry) { I18n.l(entry.created_at, format: :long) },
        sections: [{
          key:   :primary,
          rows:  columns.map { |c|
            { key: c[:key], label: c[:label], value: c[:value], format: c[:format], hideable: c[:hideable] }
          }
        }]
      )
    end

    def self.format_for(type)
      case type.to_s.downcase
      when "money", "currency"           then :money
      when "number", "integer", "decimal" then :number
      when "datetime", "timestamp"       then :datetime
      when "date"                        then :date
      else                                    :string
      end
    end

    def self.align_for(type)
      %w[money currency number integer decimal].include?(type.to_s.downcase) ? :right : :left
    end

    def self.data_reader(slug)
      ->(entry) { entry.respond_to?(:data_json) ? entry.data_json[slug] : nil }
    end

    # Display text from the Entities::EntryDisplay the controller attached.
    def self.display_reader(slug)
      ->(entry) { entry.respond_to?(:display_text) ? entry.display_text(slug) : nil }
    end

    # Calculated stays off the member surface. Fields hidden from members and
    # the owner reference (always the signed-in member) are omitted too.
    def self.member_surface_field?(field, owner_slug = nil)
      return false if field["type"] == "Calculated"

      slug = (field["name_slug"] || field["key"]).to_s
      return false if owner_slug.present? && slug == owner_slug.to_s

      EntityAttributeAudience.visible_to?(field, EntityAttributeAudience::MEMBER)
    end
    private_class_method :member_surface_field?, :data_reader, :display_reader, :omit_owner_rows
  end
end
