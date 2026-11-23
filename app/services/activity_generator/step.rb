# frozen_string_literal: true

class ActivityGenerator
  # One Railway step: a canvas element plus everything the generator decides
  # about it — its method name, Subprocess target, route signals and wiring.
  Step = Struct.new(
    :element, :method_name, :subprocess,
    :route_module, :branches,
    :done_signal, :done_connection_id, :body_id, :exit_id,
    :magnetic, :outputs,
    keyword_init: true
  ) do
    def element_id = element["id"]

    def type = element["type"]

    def decision? = type == "decision"

    def loop? = type == "loop"

    # The WiringPlanner's view of the step.
    def kind
      case type
      when "decision" then :decision
      when "subflow" then :subflow
      when "loop" then :loop
      when "end" then :end_response
      else :step
      end
    end

    # Signal constants declared under Routes::<route_module>.
    def route_constants
      decision? ? Array(branches).map { |branch| branch[:const_name] } : ["Done"]
    end
  end
end
