# frozen_string_literal: true

module AiAssistant
  module Subsystems
    # The entity stage of a build: designs the entities the flows need. An
    # existing entity of an object's name is reused when it covers what the
    # flows need; the rest come from one completion written as create_entity
    # arguments, checked by Coverage and then written through the
    # create_entity operation, so its validation, quota and audit apply.
    # Problems from either go back to the model for repair.
    class AuthorEntities
      Result = Struct.new(:ok, :entities, :errors, keyword_init: true)
      ATTEMPTS = 3

      def self.call(...) = new(...).call

      def initialize(build:, flows:, chat:)
        @build = build
        @flows = flows
        @chat = chat
        @needs = EntityNeeds.call(flows: flows, brief: build.brief)
      end

      def call
        gaps = Coverage.call(needs: existing_needs, definitions: existing_definitions, customer_id: customer.id, logins: logins?)
        return failed(gaps, user_errors: existing_gaps) if gaps.any?
        return done if new_needs.empty?

        author
      end

      private

      def customer = @build.customer
      def logins? = @build.brief.logins?
      def person_model = EntityDefinitions::Capabilities.person_model(customer.id)

      def existing
        @existing ||= @needs.to_h { |need| [need.key, reusable(need)] }.compact
      end

      # The customer's own entity of the need's name, gaps and all; a shared
      # one only when it covers the need, else the customer gets its own.
      def reusable(need)
        entity = named(need.name)
        return entity unless entity&.shared?

        entity if Coverage.call(needs: [need], definitions: { need.key => definition_of(entity) }, customer_id: customer.id, logins: logins?).empty?
      end

      # The customer's own entity wins over a shared one of the same name.
      def named(name)
        Entity.where(customer_id: [customer.id, nil]).where("LOWER(name) = ?", name.downcase)
              .order(Arel.sql("customer_id IS NULL"), :id).first
      end

      def existing_needs = @needs.select { |need| existing.key?(need.key) }
      def new_needs = @needs.reject { |need| existing.key?(need.key) }

      def existing_definitions = existing.transform_values { |entity| definition_of(entity) }

      def definition_of(entity) = { "property_schema" => Array(entity.property_schema_json), "extended_model" => entity.extended_model }

      # Gaps of a reused entity name its fields only, which the admin can act on.
      def existing_gaps
        existing_needs.filter_map do |need|
          problems = Coverage.call(needs: [need], definitions: existing_definitions.slice(need.key), customer_id: customer.id, logins: logins?)
          I18n.t("ai_assistant.subsystems.build.entity_gaps", name: existing[need.key].display_label.presence || need.name) if problems.any?
        end
      end

      def author
        messages = [{ role: "system", content: system_prompt }, { role: "user", content: instruction }]
        problems = []
        ATTEMPTS.times do
          text = complete(messages)
          return failed(["The model did not reply."]) if text.nil?

          problems = attempt(AiAssistant::Assistant::JsonDocument.parse(text))
          return done if problems.empty?

          messages += [{ role: "assistant", content: text }, { role: "user", content: repair(problems) }]
        end
        failed(problems)
      end

      # The problems of one reply; empty once its entities are written.
      def attempt(reply)
        return ["Reply with one JSON object only."] unless reply.is_a?(Hash)

        input = reply.merge("domain" => domain_name)
        violations, = Operations.for("create_entity").input_schema(operation_context).validate(input)
        return described(violations) if violations.any?

        problems = problems_of(input)
        return problems if problems.any?

        outcome = create(input)
        outcome.ok? ? [] : described(outcome.violations)
      end

      def described(violations)
        I18n.with_locale(I18n.default_locale) { violations.map { |violation| "#{violation.pointer}: #{violation.message}" } }
      end

      def problems_of(input)
        mapper = EntityDefinitions::Api::Mapper.new(customer: customer)
        definitions = Array(input["entities"]).grep(Hash).to_h do |spec|
          [spec["name"].to_s.squish.downcase, mapper.to_definition(spec)]
        end
        Coverage.call(needs: new_needs, definitions: definitions, customer_id: customer.id, logins: logins?)
      end

      def create(input)
        Operations::Activities::Execute.call(operation: "create_entity", input: input, context: operation_context)
      end

      def done
        entities = @needs.to_h do |need|
          entity = named(need.name)
          [need.name, entity && { "id" => entity.id, "name" => entity.display_label.presence || entity.name, "created" => !existing.key?(need.key) }]
        end
        missing = entities.select { |_name, row| row.nil? }.keys
        return failed(missing.map { |name| "Entity #{name} is missing." }) if missing.any?

        Result.new(ok: true, entities: entities, errors: [])
      end

      def complete(messages)
        result = @chat.call(messages)
        text = result.is_a?(Hash) ? result[:text].to_s.strip : ""
        text if result.is_a?(Hash) && result[:outcome] == :success && text.present?
      end

      def domain_name = EntityDomain.for_customer(customer.id).find_by(id: @build.results_json["domain_id"])&.name || @build.name

      def system_prompt
        definition = Operations.for("create_entity").tool_definition(operation_context)
        AiAssistant::Assistant::Prompt::Document.read("subsystem_entities")
                                               .gsub("{guide}") { AiAssistant::Assistant::Prompt::Document.read("entity_authoring") }
                                               .gsub("{schema}") { JSON.pretty_generate(definition[:parameters]) }
      end

      def operation_context
        Operations::Context.new(customer: customer, actor: @build.user, channel: "assistant", conversation: @build.conversation)
      end

      def instruction
        reusable = existing.values.map { |entity| "- #{entity.name} (exists; reference it by this name)" }
        [
          "Domain: #{domain_name}",
          "## Entities to create\n#{EntityNeeds.describe(new_needs, person_model: person_model, logins: logins?)}",
          reusable.any? ? "## Entities that already exist\n#{reusable.join("\n")}" : nil,
          "## Business rules\n#{rules}"
        ].compact.join("\n\n")
      end

      def rules
        list = Array(@build.brief.to_h["rules"]).map { |rule| "- #{rule}" }
        list.any? ? list.join("\n") : "- (none)"
      end

      def repair(problems)
        "Fix these problems and reply with the whole corrected create_entity arguments JSON object only:\n" \
          "#{problems.map { |problem| "- #{problem}" }.join("\n")}"
      end

      def failed(problems, user_errors: [])
        Rails.logger.warn("#{Build::LOG_TAG} build=#{@build.id} entities unusable: #{problems.join(' | ')}")
        Result.new(ok: false, entities: {}, errors: user_errors.presence || [I18n.t("ai_assistant.subsystems.build.entities_failed")])
      end
    end
  end
end
