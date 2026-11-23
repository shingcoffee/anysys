# frozen_string_literal: true

module Operations
  class SetPageProcessing < Base
    key "set_page_processing"
    version 1
    title "Set page processing"
    summary "Set what happens when one of this workspace's form pages is submitted, by naming form processing the workspace already has, replacing what the page uses now. Name the page by the action key and audience list_catalog lists under pages, and the processing by name. A launched page accepts only launched processing that fits its entity. Does not create or change processing. Applies immediately."
    schema "set_page_processing.json"
    annotations destructive: false, confirmation: :never

    register!

    def validate(input)
      violations = []
      violations << page_missing(input) unless target_page(input)
      violations << processing_missing(input["processing"]) unless target_processing(input["processing"])
      violations
    end

    def plan(input)
      page = target_page(input)
      page ? [{ "kind" => "page", "action" => "updated", "name" => page.name }] : []
    end

    def perform(input)
      page = target_page(input)
      processing = target_processing(input["processing"])
      result = Pages::Activities::BindFlowchart.call(page: page, flowchart_id: processing.id)
      unless result.ok
        return Outcome.invalid(operation: self.class.key, violations: [
          Violation.new(pointer: "/processing", code: "page.processing_refused",
                        details: { "page" => page.name, "name" => processing.name, "errors" => refusal(result) })
        ])
      end

      Outcome.succeeded(
        operation: self.class.key,
        data: { "page" => page.action_key, "audience" => input["audience"], "processing" => processing.name },
        effects: [{ "kind" => "page", "action" => "updated", "name" => page.name }]
      )
    end

    private

    def target_page(input)
      @target_page ||= Page.where(customer_id: context.customer.id, action_key: input["page"])
                           .for_audience(input["audience"]).order(:id).first
    end

    def target_processing(name)
      @target_processing ||= Flowchart.where(customer_id: [context.customer.id, nil], name: name.to_s.strip)
                                      .where.not(status: :deleted)
                                      .order(Arel.sql("customer_id IS NULL"), :id).first
    end

    # The detailed reasons name flowcharts and their steps, which only the
    # platform owner sees.
    def refusal(result)
      FlowchartVisibility.allowed?(context.actor) ? result.errors : result.reasons
    end

    def page_missing(input)
      Violation.new(pointer: "/page", code: "page.not_found", details: { "key" => input["page"], "audience" => input["audience"] })
    end

    def processing_missing(name)
      known = Flowchart.where(customer_id: [context.customer.id, nil]).where.not(status: :deleted).pluck(:name)
      Violation.new(pointer: "/processing", code: "processing.not_found",
                    details: { "name" => name.to_s.strip, "candidates" => Violation.candidates(name, known) })
    end
  end
end
