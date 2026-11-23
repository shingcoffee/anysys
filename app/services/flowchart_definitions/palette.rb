# frozen_string_literal: true

module FlowchartDefinitions
  # Machine-readable catalog of palette categories, step actions, and
  # structural element types for the assistant flowchart prompt.
  # Step actions come from CodeGenerators::ActionCatalog.export.
  class Palette
    ELEMENT_TYPES = %w[start end process decision loop subflow].freeze

    # Behaviour the element config_schema cannot express. Field names, roles,
    # defaults and visibility come from ElementCatalog via SchemaGenerator.
    ELEMENT_DOCS = [
      {
        "type" => "start",
        "description" => "Entry point. Exactly one per flowchart, with no incoming connections; every other " \
                         "element must be reachable from it. No config fields: the run's seeded variables " \
                         "(params, bound_entity, customer_id, current_user_id, audience, locale) are already in " \
                         "ctx when it starts.",
        "properties" => {
          "label" => "Display label",
          "description" => "Optional notes"
        }
      },
      {
        "type" => "end",
        "description" => "Exit point. At least one per flowchart, with no outgoing connections. Reaching any End " \
                         "finishes the run successfully; to refuse, use a failing step instead. responseType " \
                         "value writes returnValue to ctx[:response] for a parent that runs this flowchart as a " \
                         "subflow; a page flowchart needs none.",
        "properties" => {
          "label" => "Display label",
          "description" => "Optional notes"
        }
      },
      {
        "type" => "process",
        "description" => "Ordered container of step actions; put the business logic here. Steps run top to " \
                         "bottom, each reading what earlier steps wrote to ctx, and the first step that fails " \
                         "refuses the submission with its message. Each step names a registered palette action " \
                         "and MUST include a config object using that action's config_fields.",
        "properties" => {
          "label" => "Display label",
          "steps" => "Array of { action (canonical ActionCatalog key), config (required object of declared fields), selectionLabels (optional) }",
          "description" => "Optional notes"
        }
      },
      {
        "type" => "decision",
        "description" => "Routes to one of >= 2 outgoing connections, listed in branch order; it never writes " \
                         "variables or refuses. Each connection carries label and matchValue; blank matchValue = Otherwise (at most one). routeBy value: matchValue is compared with subject, values unique. routeBy condition: matchValue \"true\" (Yes, required), \"false\" (No) or blank. Every conditions field is a flat group {type: \"group\", joins: [\"AND\"|\"OR\" per gap], conditions: [{kind: \"field\", leftOperand, operator, rightOperand}]}.",
        "properties" => {
          "label" => "Display label",
          "description" => "Optional notes"
        }
      },
      {
        "type" => "loop",
        "description" => "Repeats its body. It has exactly two outgoing connections: one into the body, whose " \
                         "last element connects back to the loop, and one exit followed when the loop finishes. " \
                         "while: runs while condition holds (runOnceFirst checks after the first pass). " \
                         "for_each: walks collection, a ctx path without the ctx. prefix, binding itemVariable " \
                         "and indexVariable for the body. Loops do not nest. Reaching maxIterations fails the run.",
        "properties" => {
          "label" => "Display label",
          "description" => "Optional notes"
        }
      },
      {
        "type" => "subflow",
        "description" => "Runs another launched flowchart (flowchartId) as one step. The child sees this run's " \
                         "variables plus any inputVariables, and what it writes comes back under the same names; " \
                         "when the child refuses, this run refuses with its messages. One outgoing connection.",
        "properties" => {
          "label" => "Display label",
          "description" => "Optional notes"
        }
      }
    ].freeze

    CONNECTION_DOC = "Directed arrow {from, to} between element ids; the run follows it when the source element " \
                     "succeeds. Only a decision has several outgoing connections: each carries matchValue (and a " \
                     "label), listed in branch order. A step that refuses the submission leaves the happy path on " \
                     "its own, so never draw failure arrows."

    def self.document
      @document ||= Assistant::SchemaGenerator.palette_document
    end

    def self.prompt
      Assistant::SchemaGenerator.prompt_palette
    end

    def self.reset!
      @document = nil
      @action_index = nil
      Assistant::SchemaGenerator.reset!
      UiConfigSchema.reset!
      StructureSchema.reset!
      Assistant::SchemaValidator.reset!
    end

    def self.human_label(key)
      key.to_s.tr("_", " ").split.map(&:capitalize).join(" ")
    end

    def self.known_action?(key)
      action_index.key?(key.to_s)
    end

    def self.action(key)
      action_index[key.to_s]
    end

    def self.canonical_key(key)
      row = action(key)
      row && row["action"]
    end

    def self.canonical_keys
      document.fetch("step_actions").map { |row| row["action"] }
    end

    def self.action_index
      @action_index ||= document.fetch("step_actions").index_by { |row| row["action"] }
    end
    private_class_method :action_index
  end
end
