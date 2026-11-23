# frozen_string_literal: true

module AiAssistant
  module Subsystems
    # Whether entity definitions (stored shape: property_schema attributes)
    # give the flows what they need (EntityNeeds): every field, the parent
    # and owner references, read-only system fields, a person that signs in,
    # and a status lifecycle allowing every change the steps make. Returns
    # plain English problems for the model; empty when covered.
    class Coverage
      SELECTION = %w[select radio].freeze
      NAME_FIELDS = %w[name full_name].freeze

      def self.call(...) = new(...).call

      # +definitions+: { need key => stored definition hash }.
      def initialize(needs:, definitions:, customer_id:, logins:)
        @needs = needs
        @definitions = definitions
        @customer_id = customer_id
        @logins = logins
      end

      def call
        @needs.flat_map do |need|
          definition = @definitions[need.key]
          next ["Entity #{need.name} is missing."] unless definition

          problems(need, definition).map { |problem| "#{need.name}: #{problem}" }
        end
      end

      private

      def problems(need, definition)
        attributes = Array(definition["property_schema"]).grep(Hash)
        list = missing_fields(need, attributes, definition)
        list += need.parents.filter_map { |parent| "add a reference to #{parent}." unless reference?(attributes, parent) }
        list << "add an owner reference to #{person_name} (owner true)." if need.owned && !owner?(attributes)
        list += writable_system_fields(need, attributes)
        list << "set extends to #{person_model}, so these people can sign in." if need.person && @logins && definition["extended_model"].blank?
        list + status_problems(need, attributes)
      end

      def missing_fields(need, attributes, definition)
        inherited = definition["extended_model"].present? ? inherited_slugs(definition["extended_model"]) : []
        (need.fields + need.system_fields).filter_map do |name|
          next if inherited.include?(slug(name)) || find(attributes, name)

          "add the field #{name}."
        end
      end

      def writable_system_fields(need, attributes)
        need.system_fields.flat_map do |name|
          attribute = find(attributes, name) or next []
          need.guarded.filter_map do |audience|
            next unless EntityAttributeAudience.editable_by?(attribute, audience)

            "make #{name} read-only for #{audience} (access.editable_by.#{audience} false)."
          end
        end
      end

      def status_problems(need, attributes)
        status = need.status or return []
        attribute = find(attributes, status["field"])
        return ["add the status field #{status['field']}."] unless attribute
        return ["make #{status['field']} a select with static options."] unless SELECTION.include?(attribute["html_type"].to_s)

        options = Array(attribute.dig("config", "options")).grep(Hash)
        values = status["states"].to_h { |state| [state, option_value(options, state)] }
        missing = values.select { |_state, value| value.nil? }.keys
        return ["give #{status['field']} the options #{missing.join(', ')}."] if missing.any?

        lifecycle = Entities::Lifecycle.from_attribute(attribute)
        return ["give #{status['field']} a lifecycle with exactly one default option, #{status['initial']}."] unless lifecycle
        return ["make #{status['initial']} the default option of #{status['field']}."] unless lifecycle.initial == values[status["initial"]]

        need.transitions.filter_map do |row|
          from = values[row["from"]]
          to = values[row["to"]]
          absent = row["by"].reject { |audience| lifecycle.permits?(from, to, audience) }
          "let #{absent.join(', ')} move #{status['field']} from #{row['from']} to #{row['to']} in its lifecycle." if absent.any?
        end
      end

      def find(attributes, name) = Flows.attribute(attributes, name)

      def reference?(attributes, entity)
        attributes.any? { |attribute| Flows.same?(attribute.dig("config", "options_entity_name"), entity) || references_id?(attribute, entity) }
      end

      def owner?(attributes)
        attributes.any? { |attribute| attribute["owner"] == true && (person_name.nil? || reference?([attribute], person_name)) }
      end

      # Stored definitions of existing entities name the referenced entity by id.
      def references_id?(attribute, entity)
        id = attribute.dig("config", "entity_id").presence or return false
        found = Entity.where(customer_id: [@customer_id, nil]).find_by(id: id)
        found && [found.name, found.display_label].any? { |label| Flows.same?(label, entity) }
      end

      def option_value(options, state)
        option = options.find { |row| [row["value"], row["label"]].any? { |text| Flows.same?(text, state) } }
        option && Entities::Lifecycle.option_value(option)
      end

      def inherited_slugs(model)
        People::IDENTITY_KEYS + NAME_FIELDS + EntityDefinitions::Capabilities.base_model_fields(@customer_id, model)
      end

      def person_name = @needs.find(&:person)&.name
      def person_model = EntityDefinitions::Capabilities.person_model(@customer_id)
      def slug(name) = EntityEntry.attribute_slug_for(name.to_s)
    end
  end
end
