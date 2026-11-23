# frozen_string_literal: true

module LoopPhase4SpecHelpers
  module_function

  def cond_group(left, operator, right = "")
    {
      "type" => "group",
      "joins" => [],
      "conditions" => [
        { "kind" => "field", "leftOperand" => left, "operator" => operator, "rightOperand" => right.to_s }
      ]
    }
  end

  def boolean_decision(left)
    { "routeBy" => "condition", "condition" => cond_group(left, "is_true") }
  end

  def value_decision(subject)
    { "routeBy" => "value", "subject" => subject }
  end
end
