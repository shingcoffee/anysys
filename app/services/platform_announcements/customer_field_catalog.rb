# frozen_string_literal: true

module PlatformAnnouncements
  # Whitelist of Customer columns the announcement audience builder may query.
  # Field identifiers are always validated against this catalog before SQL —
  # there is no free-form column input. Enum columns (industry/tier/status)
  # are typed as string so operators compare against enum keys ("premium"),
  # not the integer storage.
  class CustomerFieldCatalog
    OPERATORS_BY_TYPE = Emails::SendActivities::FieldCatalog::OPERATORS_BY_TYPE

    ENUM_OPERATORS = %w[equals not_equals is_blank is_present].freeze

    ENUM_COLUMNS = %w[industry tier status].freeze

    FIELDS = [
      { field: "id", column: "id", type: :integer },
      { field: "name", column: "name", type: :string },
      { field: "alias", column: "alias", type: :string },
      { field: "industry", column: "industry", type: :string, enum: true },
      { field: "tier", column: "tier", type: :string, enum: true },
      { field: "status", column: "status", type: :string, enum: true },
      { field: "locale", column: "locale", type: :string },
      { field: "contact", column: "contact", type: :string },
      { field: "phone", column: "phone", type: :string },
      { field: "address", column: "address", type: :string },
      { field: "created_at", column: "created_at", type: :datetime },
      { field: "updated_at", column: "updated_at", type: :datetime }
    ].freeze

    def fields
      @fields ||= FIELDS.map { |spec| build(spec) }
    end

    # Returns the typed field and its permitted operators, or nil.
    def resolve(identifier)
      fields.find { |f| f[:field] == identifier.to_s }
            &.slice(:association, :column, :type, :enum, :operators)
    end

    private

    def build(spec)
      enum = spec[:enum] == true
      {
        field:       spec[:field],
        association: nil,
        column:      spec[:column],
        type:        spec[:type],
        enum:        enum,
        label:       I18n.t("maint_platform.announcements.fields.#{spec[:field]}"),
        operators:   enum ? ENUM_OPERATORS : OPERATORS_BY_TYPE.fetch(spec[:type], OPERATORS_BY_TYPE[:string])
      }
    end
  end
end
