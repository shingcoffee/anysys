# frozen_string_literal: true

# Factory helpers for building Flowchart instances from named templates.
# Provides +new_with_defaults+ (public) and the private builder primitives
# used to assemble default and template configurations.
module Flowchart::TemplateBuilder
  extend ActiveSupport::Concern

  STEP_CONFIGS = {
    "build_contract" => { "contractClass" => "EntityEntryContract", "modelVariable" => "model" },
    "validate_contract" => {},
    "register_member" => { "personVar" => "model", "identityVar" => "identity", "resultVar" => "registration" },
    "save_model" => {}
  }.freeze

  # The page seeds ctx[:model] with the record it submits (new or edited), so
  # saving it needs no find/new step.
  PAGE_RECORD_ACTIONS = %w[build_contract validate_contract save_model].freeze
  # A public sign-up page: register_member creates the account and saves the
  # person record with its identity, then save_model writes the page's fields.
  MEMBER_SIGNUP_ACTIONS = %w[build_contract validate_contract register_member save_model].freeze

  class_methods do
    # Build a new, unsaved Flowchart pre-populated with a sensible default
    # configuration (or the named template when +:template+ is supplied).
    # A present +template+ wins over a posted +configuration+.
    def new_with_defaults(attributes = {})
      attributes = attributes.to_h.dup
      template_key = attributes.delete("template") || attributes.delete(:template)
      if template_key.present?
        attributes.delete("configuration")
        attributes.delete(:configuration)
      end
      flowchart = new(attributes)
      if template_key.present? || flowchart.configuration.blank?
        config = template_key.present? ? (template_configurations[template_key] || default_configuration) : default_configuration
        flowchart.configuration_json = config
      end
      flowchart
    end

    # Returns a hash mapping template keys to their full configuration hashes.
    def template_configurations
      {
        "blank" => default_configuration,
        "page_record" => chain_configuration(PAGE_RECORD_ACTIONS),
        "member_signup" => chain_configuration(MEMBER_SIGNUP_ACTIONS)
      }
    end

    private

    def default_configuration
      chain_configuration([])
    end

    def chain_configuration(actions)
      types = ["start", *Array(actions).map { "process" }, "end"]
      elements = types.map.with_index do |type, index|
        action = type == "process" ? actions[index - 1] : nil
        label_key = action || type
        properties =
          case type
          when "start" then default_start_properties
          when "end" then {}
          else
            {
              "inputs" => [],
              "outputs" => [],
              "steps" => [{
                "action" => action,
                "config" => STEP_CONFIGS.fetch(action).dup,
                "selectionLabels" => [template_label(label_key)]
              }]
            }
          end
        {
          "id" => "el_#{index + 1}",
          "type" => type,
          "x" => 400,
          "y" => 80 + (index * 100),
          "width" => 100,
          "height" => 45,
          "label" => template_label(label_key),
          "properties" => properties
        }
      end
      connections = elements.each_cons(2).map.with_index do |(from, to), index|
        {
          "id" => "c#{index + 1}",
          "from" => from["id"],
          "to" => to["id"],
          "fromPosition" => "bottom",
          "toPosition" => "top"
        }
      end

      {
        "elements" => elements,
        "connections" => connections,
        "metadata" => {
          "canvas" => { "width" => 2000, "height" => 1500 },
          "created_at" => Time.current.iso8601
        }
      }
    end

    def template_label(key)
      FlowchartDefinitions::ActionLabel.for(key)
    end

    def default_start_properties
      {
        "inputs" => [{ "value" => "all params" }],
        "outputs" => [{ "value" => "ctx" }],
        "description" => ""
      }
    end
  end
end
