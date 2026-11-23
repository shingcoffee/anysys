# frozen_string_literal: true

module Admin
  module Entities
    # Resolves admin entity-entry index columns from schema + per-customer preference.
    # Sorting and search read each column's `sql:`; cells read the
    # Entities::EntryDisplay built for the rows being rendered.
    class ColumnsBuilder
      SYSTEM_KEYS = %i[id created_at updated_at].freeze
      TYPE_MAP = {
        "number" => :number, "range" => :number,
        "date" => :date, "month" => :date, "week" => :date,
        "datetime-local" => :datetime, "time" => :datetime,
        "select" => :badge, "radio" => :badge,
        "textarea" => :truncate
      }.freeze
      NUMERIC_HTML_TYPES = FlowchartRuntime::FormulaCompiler::NUMERIC_HTML_TYPES
      PERSON_NAME_ATTRIBUTES = %w[first_name last_name].freeze
      PERSON_IDENTITY_ATTRIBUTES = [*PERSON_NAME_ATTRIBUTES, "email"].freeze

      def self.call(entity:, setting:, customer_id:, display:, t: I18n.method(:t))
        new(entity:, setting:, customer_id:, display:, t:).call
      end

      def initialize(entity:, setting:, customer_id:, display:, t:)
        @entity = entity
        @setting = setting
        @customer_id = customer_id
        @display = display
        @t = t
      end

      def call
        [system_column(:id), *person_columns, *attribute_columns, *extended_attribute_columns,
         system_column(:created_at), system_column(:updated_at)]
      end

      private

      def attribute_columns
        selected_slugs.map { |slug| derived_fields_by_slug.key?(slug) ? derived_column(slug) : attribute_column(slug) }
      end

      def selected_slugs
        preferred = @setting.visible_column_keys
        if preferred.nil?
          default_slugs
        else
          preferred.map(&:to_s) & (candidate_slugs + derived_candidate_slugs)
        end
      end

      # No saved preference shows every stored field. Calculated and computed
      # fields stay out until someone picks them.
      def default_slugs
        candidate_slugs
      end

      def candidate_slugs
        @candidate_slugs ||= begin
          system = SYSTEM_KEYS.map(&:to_s)
          @entity.input_fields
                 .filter_map { |f| f["name_slug"].presence }
                 .reject { |slug| system.include?(slug) }
        end
      end

      def fields_by_slug
        @fields_by_slug ||= @entity.input_fields.index_by { |f| f["name_slug"] }
      end

      def attribute_column(slug)
        field = fields_by_slug[slug] || {}
        type = TYPE_MAP.fetch(field["html_type"].to_s, :text)
        display = @display

        col = {
          key: slug.to_sym,
          label: heading_for(field, slug),
          type: type,
          sortable: true,
          searchable: %i[text truncate badge].include?(type),
          sql: "json_extract(entity_entries.data, '$.#{slug}')",
          cell: ->(row) { display.text(row, slug) }
        }
        col[:align] = :right if type == :number
        col[:relative] = true if type == :datetime
        col[:truncate] = 60 if type == :truncate
        col[:badge] = badge_for(slug) if type == :badge
        col
      end

      def badge_for(slug)
        display = @display
        blank = I18n.t("common.labels.em_dash")
        ->(row) {
          label = display.text(row, slug)
          label == blank ? nil : { label: label, variant: :default }
        }
      end

      def derived_expressions
        @derived_expressions ||= ::Entities::DerivedExpressions.for(@entity, customer_id: @customer_id)
      end

      def derived_candidate_slugs
        derived_expressions.map { |expression| expression[:name] }
      end

      def derived_fields_by_slug
        @derived_fields_by_slug ||= (@entity.computed_fields + @entity.calculated_fields).index_by { |f| f["name_slug"] }
      end

      def derived_column(slug)
        field = derived_fields_by_slug[slug] || {}
        number = field["type"] == Entity::COMPUTED_TYPE || NUMERIC_HTML_TYPES.include?(field["html_type"].to_s)
        display = @display

        col = {
          key: slug.to_sym,
          label: heading_for(field, slug),
          type: number ? :number : :text,
          sortable: true,
          searchable: false,
          derived: true,
          sql: derived_expressions.find { |expression| expression[:name] == slug }&.dig(:sql),
          cell: ->(row) { display.text(row, slug) }
        }
        col[:align] = :right if number
        col
      end

      def extended_link
        @extended_link ||= ExtendedModels::Attributes.link(@entity.extended_model)
      end

      def person_link
        extended_link if @entity.person?
      end

      # A person entry leads with its user's full name, linked to the user's
      # page, and email — whatever extended attributes are selected.
      def person_columns
        link = person_link
        return [] unless link

        blank = @t.call("common.labels.em_dash")
        association = link.name
        customer_id = @customer_id
        routes = Rails.application.routes.url_helpers
        full_name = {
          key: :"#{association}_full_name",
          label: @t.call("admin_misc.entities.columns.user_full_name"),
          type: :text,
          sortable: true,
          searchable: true,
          sql: extended_attribute_sql(link, *PERSON_NAME_ATTRIBUTES),
          cell: ->(row) {
            record = row.public_send(association)
            PERSON_NAME_ATTRIBUTES.filter_map { |name| record&.public_send(name).presence }.join(" ").presence || blank
          },
          href: ->(row) {
            record = row.public_send(association)
            routes.admin_modules_authentication_user_path(customer_id, record) if record
          }
        }
        [full_name, extended_attribute_column(link, "email")]
      end

      # Allowed columns of the extended model, read from the preloaded record.
      # The subquery is only for sort and search, and stays in the entry's tenant
      # when both tables have customer_id.
      def extended_attribute_columns
        link = extended_link
        return [] unless link

        attributes = ExtendedModels::Attributes.allowed(link.class_name, customer_id: @customer_id)
        attributes -= PERSON_IDENTITY_ATTRIBUTES if person_link
        attributes.map { |attribute| extended_attribute_column(link, attribute) }
      end

      def extended_attribute_column(link, attribute)
        blank = @t.call("common.labels.em_dash")
        association = link.name
        type = extended_type(link.klass.columns_hash[attribute])
        {
          key: :"#{association}_#{attribute}",
          label: attribute_label(attribute),
          type: type,
          sortable: true,
          searchable: type == :text,
          sql: extended_attribute_sql(link, attribute),
          cell: ->(row) {
            record = row.public_send(association)
            value = record&.public_send(attribute)
            value.nil? || value == "" ? blank : value
          }
        }
      end

      def attribute_label(name)
        key = "common.labels.#{name}"
        I18n.exists?(key) ? @t.call(key) : name
      end

      def extended_type(column)
        case column&.type
        when :integer, :decimal, :float then :number
        when :datetime, :timestamp then :datetime
        when :date then :date
        when :boolean then :boolean
        else :text
        end
      end

      # Several attributes are joined with a space (e.g. first and last name).
      def extended_attribute_sql(link, *attributes)
        table = quote_name(link.klass.table_name)
        value = attributes.map { |attribute| "#{table}.#{quote_name(attribute)}" }.join(" || ' ' || ")
        primary_key = quote_name(link.klass.primary_key)
        foreign_key = quote_name(link.foreign_key)
        clauses = ["#{table}.#{primary_key} = entity_entries.#{foreign_key}"]
        if link.klass.column_names.include?("customer_id")
          clauses << "#{table}.customer_id = entity_entries.customer_id"
        end
        "(SELECT #{value} FROM #{table} WHERE #{clauses.join(' AND ')})"
      end

      def quote_name(name)
        raise ArgumentError, "unsafe identifier" unless name.to_s.match?(/\A[a-z][a-z0-9_]*\z/)

        ActiveRecord::Base.connection.quote_column_name(name)
      end

      def heading_for(field, slug)
        field["display_label"].presence || field["name"].presence || slug.to_s
      end

      def system_column(key)
        {
          key: key,
          label: @t.call("admin_misc.entities.columns.#{key}"),
          sortable: true,
          type: (key == :id ? :number : :datetime),
          relative: (key != :id),
          align: (key == :id ? :right : :left)
        }
      end
    end
  end
end
