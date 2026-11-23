# frozen_string_literal: true

module FlowchartDefinitions
  module Assistant
    # Name-match updates of live (non-deleted) customer-owned flowcharts
    # require an explicit confirmation from the first persistable document,
    # unless the caller already approved replacing that one flowchart.
    class UpdatePolicy
      Decision = Struct.new(:existing_names, :confirmed, keyword_init: true) do
        def permitted?
          existing_names.empty? || confirmed
        end
      end

      def self.call(flowchart:, customer:, confirmed: false, replaceable: nil)
        new(flowchart: flowchart, customer: customer, confirmed: confirmed, replaceable: replaceable).call
      end

      def initialize(flowchart:, customer:, confirmed: false, replaceable: nil)
        @flowchart = flowchart
        @customer = customer
        @confirmed = Extraction.boolean(confirmed)
        @replaceable = replaceable.to_s
      end

      def call
        names = existing_names
        Decision.new(existing_names: names, confirmed: @confirmed || (@replaceable.present? && names == [@replaceable]))
      end

      private

      def proposed_name
        return "" unless @flowchart.is_a?(Hash)

        @flowchart.stringify_keys["name"].to_s.strip
      end

      def existing_names
        name = proposed_name
        return [] if name.blank? || @customer.blank?

        match = Flowchart.where(customer_id: @customer.id, name: name).first
        match ? [match.name] : []
      end
    end
  end
end
