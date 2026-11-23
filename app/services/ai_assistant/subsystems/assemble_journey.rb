# frozen_string_literal: true

module AiAssistant
  module Subsystems
    # Turns one journey of a build's flows into launched pages and a draft
    # journey, once the entities exist:
    # - a start record becomes a record step (with its status condition),
    #   and staff creating the person's account opens with a user step;
    # - create steps get a create page, add steps a repeatable page locking
    #   the parent record in, update steps a page editing the record an
    #   earlier step holds; each page shows the step's fields plus whatever
    #   else a new record requires, without the member's owner reference;
    # - a step with a skip rule is one an earlier step's processing may leave
    #   out (the processing itself carries the rule, ProcessingBrief);
    # - a public sign-up page carries the account fields and the sign-up
    #   processing, and finishes on the member journey it continues to.
    # Runs under the customer lock in one transaction, so a failure leaves no
    # stray pages.
    class AssembleJourney
      Result = Struct.new(:ok, :journey, :pages, :first_action_key, :errors, keyword_init: true)
      RECORD = "record"
      USER = "user"
      FINISH = "finish"
      KINDS = { "create" => "create", "add" => "relate", "update" => "update" }.freeze
      PUBLIC = EntityAttributeAudience::PUBLIC
      ADMIN = EntityAttributeAudience::ADMIN

      def self.call(...) = new(...).call

      # +entities+: { object name => { "id" } }; +built+: the rows of the
      # journeys this build already assembled, by key.
      def initialize(customer:, domain:, flows:, brief:, journey:, entities:, built:)
        @customer = customer
        @domain = domain
        @flows = flows
        @brief = brief
        @journey = journey
        @entities = entities
        @built = built
        @errors = []
        @pages = {}
        @factory = Journeys::PageFactory.new(customer: customer, errors: @errors)
      end

      def call
        Current.set(customer: @customer, shared_resources_mode: false) do
          result = nil
          @customer.with_lock(requires_new: true) do
            result = assemble
            raise ActiveRecord::Rollback unless result.ok
          end
          result
        end
      end

      private

      def audience = @flows.audience(@journey)
      def steps = @flows.steps(@journey)
      def start = @flows.start(@journey)

      def assemble
        rows = page_rows
        return failed unless rows

        definition = { "steps" => [*opening, *rows, finish(rows)] }
        journey = Journey.create!(
          customer: @customer, entity_domain: @domain, status: :draft, visible_audiences: [audience],
          key: unique_key(@journey["key"]), name: @journey["name"].to_s.first(120),
          description: @journey["description"].to_s.squish.presence, definition: definition.to_json
        )
        Result.new(ok: true, journey: journey, pages: @pages, first_action_key: rows.first["action_key"], errors: [])
      rescue ActiveRecord::RecordInvalid => e
        @errors.concat(e.record.errors.full_messages)
        failed
      end

      def opening
        if start
          [{ "key" => RECORD, "kind" => "record", "entity_id" => entity_for(start["object"]).id.to_s, "when" => start_condition }.compact]
        elsif staff_account?
          [{ "key" => USER, "kind" => "user" }]
        else
          []
        end
      end

      # Staff create the account first when the journey adds a person who signs in.
      def staff_account?
        audience == ADMIN && @brief.staff_accounts? && Flows.same?(steps.first&.dig("object"), @flows.person&.dig("name"))
      end

      def start_condition
        object = @flows.object(start["object"])
        listed = Array(start["status_in"])
        return if listed.empty? || @flows.status(object).nil?

        attribute = attribute_of(entity_for(object["name"]), @flows.status(object)["field"])
        return unless attribute

        { "field" => attribute["name_slug"], "in" => listed.filter_map { |state| option_value(attribute, state) } }
      end

      # nil as soon as one step's page can't be built.
      def page_rows
        steps.each_with_index.map do |step, index|
          page = page_for(step, index, last: index == steps.size - 1)
          return unless page

          @pages[step["key"].to_s] = page.id
          row(step, page)
        end
      end

      def row(step, page)
        row = { "key" => step["key"], "kind" => KINDS.fetch(step["kind"]), "action_key" => page.action_key, "label" => step["label"].to_s.first(80) }
        row["optional"] = true if step["optional"] == true
        row["conditional"] = true if step["skip"].is_a?(Hash)
        case step["kind"]
        when "add" then row.merge("inputs" => { page.page_inputs.first["field"] => source_key(step["parent"]) }, "repeat" => true)
        when "update" then row.merge("record" => source_key(step["edits"]))
        else row
        end
      end

      def source_key(key) = key.to_s == Flows::START ? RECORD : key.to_s

      def page_for(step, index, last:)
        entity = entity_for(step["object"])
        signup = index.zero? && @flows.public?(@journey) ? signup_flowchart : nil
        return if index.zero? && @flows.public?(@journey) && signup.nil?

        inputs = step["kind"] == "add" ? [parent_input(step, entity)].compact : []
        if step["kind"] == "add" && inputs.empty?
          @errors << I18n.t("ai_assistant.subsystems.build.link_missing", name: step["label"])
          return
        end

        @factory.create(
          entity, "#{@journey['key']}_#{step['key']}", audience,
          name: "#{@journey['name']}: #{step['label']}", inputs: inputs, drop: drops(entity), only: kept(step, entity, inputs),
          modes: step["kind"] == "update" ? %w[update] : %w[create], signup: signup,
          success_message: last ? @journey["finish_message"].presence : nil
        )
      end

      def signup_flowchart
        Flowcharts::SignUpPageFlowchart.for_customer(@customer).tap do |flowchart|
          @errors << I18n.t("journeys.generate.signup_unavailable") unless flowchart
        end
      end

      # The rows' reference to the record an earlier step (or the start) holds.
      def parent_input(step, entity)
        parent_object = @flows.source_object(@journey, step["parent"]) or return
        parent = entity_for(parent_object["name"])
        attribute = references(entity, parent).min_by { |row| row["owner"] == true ? 1 : 0 } or return
        { "field" => attribute["name_slug"], "entity_id" => parent.id.to_s }
      end

      def references(entity, parent)
        schema(entity).select do |attribute|
          config = attribute["config"].is_a?(Hash) ? attribute["config"] : {}
          Flows.same?(config["options_entity_name"], parent.name) || (config["entity_id"].present? && config["entity_id"].to_s == parent.id.to_s)
        end
      end

      # A member's record names them through the owner reference the submit fills in.
      def drops(entity)
        return [] unless audience == EntityAttributeAudience::MEMBER

        [People::Ownership.owner_reference(entity)&.slug].compact.map(&:to_s)
      end

      # The step's fields, the locked input, and on a new record every other
      # field this audience must fill in.
      def kept(step, entity, inputs)
        named = Array(step["fields"]).filter_map { |name| attribute_of(entity, name)&.dig("name_slug") }
        required = step["kind"] == "update" ? [] : required_slugs(entity, step)
        (inputs.map { |input| input["field"] } + named + required).map(&:to_s).uniq - drops(entity)
      end

      def required_slugs(entity, step)
        system = Array(step["system_fields"]).filter_map { |name| attribute_of(entity, name)&.dig("name_slug") }
        schema(entity).filter_map do |attribute|
          next unless Array(attribute["validators"]).any? { |validator| validator.is_a?(Hash) && validator["type"] == "presence" }
          next unless EntityAttributeAudience.editable_by?(attribute, audience)

          attribute["name_slug"] unless system.include?(attribute["name_slug"]) || attribute["owner"] == true
        end
      end

      def finish(rows)
        if @flows.public?(@journey) && (follow = @built.dig(@journey["continues_to"].to_s, "first_action_key"))
          return { "key" => FINISH, "kind" => "finish", "target" => { "kind" => "page", "action_key" => follow } }
        end

        holder = start ? RECORD : rows.find { |row| row["kind"] == "create" }&.dig("key")
        { "key" => FINISH, "kind" => "finish", "target" => { "kind" => "record", "step" => holder } }
      end

      def entity_for(name)
        id = @entities.find { |object, _row| Flows.same?(object, name) }&.last&.dig("id")
        Entity.where(customer_id: [@customer.id, nil]).find(id)
      end

      def schema(entity) = Array(entity.property_schema_json).grep(Hash)
      def attribute_of(entity, name) = Flows.attribute(schema(entity), name)

      def option_value(attribute, state)
        option = Array(attribute.dig("config", "options")).grep(Hash).find { |row| [row["value"], row["label"]].any? { |text| Flows.same?(text, state) } }
        option && Entities::Lifecycle.option_value(option)
      end

      def unique_key(base)
        (1..).lazy.map { |attempt| attempt == 1 ? base : "#{base}_#{attempt}" }.find { |key| !Journey.where(customer_id: @customer.id).exists?(key: key) }
      end

      def failed = Result.new(ok: false, pages: {}, errors: @errors.uniq.presence || [I18n.t("ai_assistant.subsystems.build.page_missing")])
    end
  end
end
