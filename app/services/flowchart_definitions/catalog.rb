# frozen_string_literal: true

module FlowchartDefinitions
  # Snapshot of live customer-owned flowcharts for the assistant prompt.
  class Catalog
    def self.for_customer(customer_id)
      new(customer_id).documents
    end

    def initialize(customer_id)
      @customer_id = customer_id
    end

    def documents
      scope.map { |flowchart| document(flowchart) }
    end

    private

    def scope
      Flowchart.where(customer_id: @customer_id).by_name
    end

    def document(flowchart)
      {
        "name" => flowchart.name,
        "status" => flowchart.status,
        "description" => flowchart.description
      }
    end
  end
end
