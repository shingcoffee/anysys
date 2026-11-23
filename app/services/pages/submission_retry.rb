# frozen_string_literal: true

module Pages
  # A refused submission's typed values and field errors, kept on the
  # visitor's run (a fresh one when they have none) so the page shows them
  # once when it renders again. Values are capped like query prefill and go
  # through Pages::Prefill again before they are shown.
  module SubmissionRetry
    KEY = "retry"

    module_function

    # The token of a newly issued run, nil when the visitor's run keeps it
    # or there is nothing to keep.
    def store(run:, page:, values:, field_errors:, customer_id:, user:, session:)
      state = { "page_id" => page.id.to_s, "values" => capped(values), "field_errors" => field_errors.to_h }
      return if state["values"].empty? && state["field_errors"].empty?

      if run
        run.update!(state: state_of(run).merge(KEY => state).to_json)
        return
      end
      JourneyRun.issue!(customer_id: customer_id, user: user, session: session, state: { KEY => state }).last
    end

    # { "values" => {}, "field_errors" => {} } kept for +page+, cleared on read.
    def take(run, page)
      data = state_of(run)
      state = data[KEY]
      return unless state.is_a?(Hash) && state["page_id"] == page.id.to_s

      run.update!(state: data.except(KEY).to_json)
      { "values" => state["values"].to_h, "field_errors" => state["field_errors"].to_h }
    end

    def capped(values)
      values.to_h.select { |_slug, value| value.is_a?(String) && value.length <= ActionLink::MAX_PREFILL_VALUE }
            .first(ActionLink::MAX_PREFILL_KEYS).to_h
    end

    def state_of(run) = run.state_json.is_a?(Hash) ? run.state_json : {}
    private_class_method :capped, :state_of
  end
end
