# frozen_string_literal: true

module FeatureModules
  # Starts the page → module handoff a page's flowchart asked for: a
  # submission_outcome["handoff"] with an already-resolved input, written by
  # FlowchartRuntime::Handoff (the "Hand off to module" and "Request payment"
  # steps).
  #
  # Returns true when an invocation was begun (the caller then sends the
  # browser to FeatureModules::HandoffsController), false when the submission
  # does not hand off. Invocation.begin! raises ModuleNotEnabled /
  # InputContractViolation / RegistrationError for the caller to surface.
  class PageHandoff
    def self.call(session:, customer:, page:, entity_entry:, outcome:, audience: nil)
      new(session: session, customer: customer, page: page, entity_entry: entity_entry, outcome: outcome,
          audience: audience).call
    end

    # +audience+: who submitted the page, so the module's default exit lands
    # them where they can go.
    def initialize(session:, customer:, page:, entity_entry:, outcome:, audience: nil)
      @session      = session
      @customer     = customer
      @page         = page
      @entity_entry = entity_entry
      @outcome      = outcome.is_a?(Hash) ? outcome.stringify_keys : {}
      @audience     = audience
    end

    def call
      request = outcome_request
      return false unless request

      FeatureModules::Invocation.begin!(
        session:         @session,
        customer:        @customer,
        triggering_page: @page,
        entity_entry:    @entity_entry,
        audience:        @audience,
        **request
      )
      true
    end

    private

    def outcome_request
      handoff = @outcome["handoff"]
      return unless handoff.is_a?(Hash)

      handoff = handoff.stringify_keys
      return if handoff["module_key"].blank?

      {
        module_key:  handoff["module_key"].to_s,
        input:       handoff["input"].is_a?(Hash) ? handoff["input"] : {},
        exit_target: handoff["exit_target"],
        on_success:  handoff["on_success"].is_a?(Hash) ? handoff["on_success"] : nil
      }
    end
  end
end
