# frozen_string_literal: true

module Emails
  module SendActivities
    # Reflection-driven catalog of queryable fields over Authentication::User
    # and its associations. Field identifiers are always validated against this
    # catalog before reaching SQL — there is no free-form column input.
    class FieldCatalog
      ROOT = Authentication::User

      # Associations exposed to the segment builder. belongs_to/has_many to
      # tenant-scoped or reference models only. Extend by adding here.
      EXPOSED_ASSOCIATIONS = %i[roles customer].freeze

      OPERATORS_BY_TYPE = {
        string:   %w[equals not_equals contains not_contains is_blank is_present],
        integer:  %w[equals not_equals greater_than less_than is_blank is_present],
        float:    %w[equals not_equals greater_than less_than is_blank is_present],
        boolean:  %w[equals not_equals],
        datetime: %w[after before is_blank is_present],
        date:     %w[after before is_blank is_present]
      }.freeze

      def fields
        @fields ||= self_fields + association_fields
      end

      # Returns { association:, column:, type: } or nil if the identifier is not
      # a known, whitelisted field. NEVER returns user-controlled column names.
      def resolve(identifier)
        fields.find { |f| f[:field] == identifier.to_s }
              &.slice(:association, :column, :type)
      end

      private

      def self_fields
        columns_for(ROOT).map do |col|
          build(field: col.name, association: nil, column: col.name, sql_type: col.type)
        end
      end

      def association_fields
        EXPOSED_ASSOCIATIONS.flat_map do |assoc_name|
          reflection = ROOT.reflect_on_association(assoc_name)
          next [] unless reflection

          columns_for(reflection.klass).map do |col|
            build(field: "#{assoc_name}.#{col.name}", association: assoc_name, column: col.name, sql_type: col.type)
          end
        end
      end

      def columns_for(klass)
        klass.columns.reject { |c| Authentication::User::SENSITIVE_COLUMNS.include?(c.name) }
      end

      def build(field:, association:, column:, sql_type:)
        type = normalize_type(sql_type)
        {
          field:       field,
          association: association,
          column:      column,
          type:        type,
          label:       field_label(field),
          operators:   OPERATORS_BY_TYPE.fetch(type, OPERATORS_BY_TYPE[:string])
        }
      end

      def field_label(field)
        attr = field.to_s.split(".").last
        common = "common.labels.#{attr}"
        return I18n.t(common) if attr.present? && I18n.exists?(common)

        field.to_s
      end

      def normalize_type(sql_type)
        case sql_type
        when :integer              then :integer
        when :float, :decimal      then :float
        when :boolean              then :boolean
        when :datetime, :timestamp then :datetime
        when :date                 then :date
        else :string
        end
      end
    end
  end
end
