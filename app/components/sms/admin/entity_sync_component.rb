# frozen_string_literal: true

module Sms
  module Admin
    class EntitySyncComponent < BaseComponent
      MAPPING_FIELDS = %i[entity_id phone_field name_field country_code timezone attribute_map_json after_entry_id through_entry_id].freeze

      def initialize(form_values:, entities:, source_fields:, sync_result:, errors:)
        @form_values, @entities, @source_fields, @sync_result, @errors = form_values || {}, entities, source_fields, sync_result, errors || {}
      end

      def batch_values(next_batch: false)
        values = @form_values.slice(*MAPPING_FIELDS)
        values[:through_entry_id] = @sync_result[:through_entry_id]
        values[:after_entry_id] = @sync_result[:next_after_entry_id] if next_batch
        values
      end

      def result_columns
        [:entry_id, :contact_id, :outcome, :error_code].map do |key|
          { key: key, label: label_text(:entity_sync, key), sortable: false,
            cell: ->(item) { key == :outcome ? label_text(:sync_outcomes, item[key]) : (key == :error_code && item[key] ? reason_label(item[key]) : item[key]) } }
        end
      end
    end
  end
end
