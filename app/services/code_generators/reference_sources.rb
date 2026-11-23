# frozen_string_literal: true

module CodeGenerators
  # Registered option sources for `reference` fields. The owner-only endpoint
  # calls `fetch(key)&.options(customer:, query:, limit: 50, **filters)`.
  module ReferenceSources
    class << self
      def fetch(key)
        registry[key.to_s]
      end

      def keys
        registry.keys
      end

      def registry
        {
          "email_templates" => EmailTemplates,
          "sms_templates" => SmsTemplates,
          "constants" => Constants,
          "entities" => Entities,
          "entity_associations" => EntityAssociations,
          "pages" => Pages,
          "flowcharts" => Flowcharts,
          "job_classes" => JobClasses,
          "service_classes" => ServiceClasses
        }
      end

      def filter(rows, query:, limit:)
        selected = Array(rows)
        if query.present?
          needle = query.to_s.downcase
          selected = selected.select do |row|
            row[:label].to_s.downcase.include?(needle) || row[:value].to_s.downcase.include?(needle)
          end
        end
        cap = limit.to_i
        cap = 50 unless cap.positive?
        selected.first(cap)
      end

      def accessible(relation, customer)
        return relation.none unless customer

        relation.where(customer_id: [customer.id, nil])
      end
    end
  end
end
