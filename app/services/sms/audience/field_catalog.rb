# frozen_string_literal: true

module Sms
  module Audience
    class FieldCatalog
      MAX_CUSTOM_FIELDS = 128
      ROOT_FIELDS = %w[name phone_e164 country_code timezone status consent_status source_kind created_at updated_at].freeze
      LABEL_KEYS = { "name" => "common.labels.name", "timezone" => "common.labels.timezone" }.freeze
      OPERATORS_BY_TYPE = {
        string: %w[equals not_equals contains not_contains is_blank is_present].freeze,
        float: %w[equals not_equals greater_than less_than is_blank is_present].freeze,
        boolean: %w[equals not_equals].freeze,
        datetime: %w[after before is_blank is_present].freeze
      }.freeze

      def initialize(customer:)
        @customer = customer
      end

      def fields
        @fields ||= root_fields + custom_specs.map { |field, type| entry(field, type.to_sym, field.delete_prefix("attributes.")) }
      end

      def resolve(identifier)
        fields.find { |entry| entry[:field] == identifier }
      end

      def root_fields
        ROOT_FIELDS.map do |field|
          entry(field, %w[created_at updated_at].include?(field) ? :datetime : :string,
            I18n.t(LABEL_KEYS.fetch(field, "sms_audience.fields.#{field}")))
        end
      end

      # Aggregate types across ALL tenant values in SQL, returning at most 128
      # keys. Sampling contacts would incorrectly expose mixed-type attributes.
      def custom_specs
        return {} unless @customer&.persisted?
        @custom_specs ||= begin
          connection = Sms::Contact.connection
          sql = case connection.adapter_name
          when "SQLite"
            <<~SQL
              SELECT j.key, MIN(CASE j.type WHEN 'text' THEN 'string' WHEN 'integer' THEN 'float'
                WHEN 'real' THEN 'float' WHEN 'true' THEN 'boolean' WHEN 'false' THEN 'boolean' ELSE 'invalid' END) AS kind
              FROM sms_contacts c, json_each(c.custom_attributes) j
              WHERE c.customer_id = ? AND j.type != 'null'
                AND length(j.key) BETWEEN 1 AND 64 AND substr(j.key, 1, 1) GLOB '[a-z]'
                AND j.key NOT GLOB '*[^a-z0-9_]*'
              GROUP BY j.key
              HAVING COUNT(DISTINCT CASE j.type WHEN 'text' THEN 'string' WHEN 'integer' THEN 'float'
                WHEN 'real' THEN 'float' WHEN 'true' THEN 'boolean' WHEN 'false' THEN 'boolean' ELSE 'invalid' END) = 1
                AND MIN(j.type) NOT IN ('array', 'object')
              ORDER BY j.key LIMIT 128
            SQL
          when "PostgreSQL"
            <<~SQL
              SELECT j.key, MIN(CASE jsonb_typeof(j.value) WHEN 'number' THEN 'float'
                WHEN 'string' THEN 'string' WHEN 'boolean' THEN 'boolean' ELSE 'invalid' END) AS kind
              FROM sms_contacts c CROSS JOIN LATERAL jsonb_each(c.custom_attributes::jsonb) j
              WHERE c.customer_id = ? AND jsonb_typeof(j.value) != 'null' AND j.key ~ '^[a-z][a-z0-9_]{0,63}$'
              GROUP BY j.key HAVING COUNT(DISTINCT jsonb_typeof(j.value)) = 1
                AND MIN(jsonb_typeof(j.value)) IN ('string', 'number', 'boolean')
              ORDER BY j.key LIMIT 128
            SQL
          else
            raise NotImplementedError, connection.adapter_name
          end
          statement = Sms::Contact.sanitize_sql_array([sql, @customer.id])
          connection.select_rows(statement).to_h.transform_keys { |key| "attributes.#{key}" }
        end
      end

      private

      def entry(field, type, label)
        { field: field, label: label, type: type, operators: OPERATORS_BY_TYPE.fetch(type) }
      end
    end
  end
end
