# frozen_string_literal: true

module AiAssistant
  module Assistant
    module Tools
      class Session
        # Both tool protocols — the JSON convention driven by
        # AiAssistant::Assistant::Loop and the native ruby_llm adapters — reach
        # a tool through #call, so this is the one place that knows a tool ran
        # and can name the progress step for it.
        PROGRESS_STEPS = {
          "list_catalog" => :catalog,
          "generate_page" => :page,
          "verify_artifact" => :verify
        }.freeze
        ENTITY_OPERATIONS = %w[create_entity update_entity get_entity].freeze
        # Rejected calls allowed per operation per turn. Successful calls do
        # not count: the budget bounds self-correction, not legitimate reads.
        MAX_ATTEMPTS = 3
        CATALOG_PAGE_LIMIT = 100

        attr_reader :effects, :viewer, :operation_outcomes, :pending_proposal

        def initialize(customer:, write_guard: nil, progress: nil, viewer: nil,
                       conversation: nil, generation: nil)
          @customer = customer
          @write_guard = write_guard
          @progress = progress || AiAssistant::Assistant::Progress.null
          @effects = []
          @viewer = viewer
          @conversation = conversation
          @generation = generation
          @operation_outcomes = []
          @pending_proposal = nil
          @failures = Hash.new(0)
        end

        def native_tools
          [
            ListCatalog.new(session: self),
            GeneratePageTool.new(session: self),
            VerifyArtifactTool.new(session: self)
          ] + operation_tools
        end

        def operation_context
          @operation_context ||= Operations::Context.new(
            customer: @customer,
            actor: actor,
            channel: "assistant",
            conversation: @conversation,
            generation: @generation
          )
        end

        # Tool results the model reads stay in the default locale even when
        # ReplyJob has switched I18n to the admin's UI locale.
        def call(name, arguments = {})
          I18n.with_locale(I18n.default_locale) { invoke(name, arguments) }
        end

        private

        def invoke(name, arguments)
          args = (arguments || {}).stringify_keys
          key = name.to_s
          return dispatch_operation(key, args) if operation?(key)

          step = PROGRESS_STEPS[key]
          @progress.start(step) if step

          case key
          when "list_catalog" then list_catalog
          when "generate_page" then guarded_write { generate_page(args["entity_name"]) }
          when "verify_artifact" then verify_artifact(args)
          else
            {
              "ok" => false,
              "error" => I18n.t("ai_assistant.assistant.tools.unknown", name: name)
            }
          end
        end

        def operation_tools
          Operations.all.filter_map do |operation|
            next unless operation.is_a?(Class) && operation < Operations::Base
            next unless operation.available?(operation_context)

            OperationTool.new(session: self, operation: operation)
          end
        end

        def operation?(key)
          Operations.keys.map(&:to_s).include?(key)
        end

        def dispatch_operation(key, args)
          @progress.start(:entity) if ENTITY_OPERATIONS.include?(key)

          if @pending_proposal && parks?(key)
            return tool_payload(
              Operations::Outcome.invalid(
                operation: key,
                violations: [
                  Operations::Violation.new(code: "proposal.already_pending", resolution: "blocked")
                ]
              )
            )
          end

          if @failures[key] >= MAX_ATTEMPTS
            return tool_payload(
              Operations::Outcome.invalid(
                operation: key,
                violations: [
                  Operations::Violation.new(code: "attempts.exhausted", resolution: "blocked")
                ]
              ),
              attempts_remaining: 0
            )
          end

          outcome = execute_operation(key, args)
          record_operation(outcome)
          return tool_payload(outcome) if outcome.ok?

          @failures[key] += 1
          tool_payload(outcome, attempts_remaining: MAX_ATTEMPTS - @failures[key])
        rescue AiAssistant::Assistant::GenerationWriteGuard::Rejected
          {
            "ok" => false,
            "error" => I18n.t("ai_assistant.assistant.tools.generation_not_current")
          }
        end

        def execute_operation(key, args)
          Operations::Activities::Execute.call(
            operation: key,
            input: args,
            context: Operations::Context.new(
              customer: @customer,
              actor: actor,
              channel: "assistant",
              conversation: @conversation,
              generation: @generation,
              idempotency_key: idempotency_key(key, args),
              around_write: around_write
            )
          )
        end

        def record_operation(outcome)
          @operation_outcomes << outcome
          record_subsystem_build(outcome)
          return unless outcome.status == "confirmation_required" && outcome.invocation

          @pending_proposal = {
            "kind" => "operation",
            "operation" => outcome.operation,
            "invocation_id" => outcome.invocation.id,
            "customer_id" => @customer.id,
            "plan" => Array(outcome.plan)
          }
        end

        # The reply that starts a build shows its state and a Cancel button.
        def record_subsystem_build(outcome)
          return unless outcome.operation == "start_subsystem_build" && outcome.status == "succeeded"

          build = AiAssistant::SubsystemBuild.unscoped.find_by(id: outcome.data&.dig("build"), customer_id: @customer.id)
          @effects << { kind: "subsystem_build", action: "started", record: build } if build
        end

        def tool_payload(outcome, attempts_remaining: nil)
          outcome.to_tool_payload(attempts_remaining: attempts_remaining)
        end

        def parks?(key)
          Operations.for(key).confirmation == :always
        rescue ArgumentError
          false
        end

        def idempotency_key(key, args)
          return if @generation.nil?

          digest = Operations::Activities::Execute.input_digest(args)
          "gen-#{@generation.id}-#{key}-#{digest}"
        end

        def around_write
          ->(&block) { AiAssistant::Assistant::GenerationWriteGuard.wrap(@write_guard, &block) }
        end

        def actor
          @conversation&.user || @viewer
        end

        def guarded_write
          return yield unless @write_guard

          @write_guard.call { yield }
        rescue AiAssistant::Assistant::GenerationWriteGuard::Rejected
          {
            "ok" => false,
            "error" => I18n.t("ai_assistant.assistant.tools.generation_not_current")
          }
        end

        def list_catalog
          mapper = EntityDefinitions::Api::Mapper.new(customer: @customer)
          {
            "ok" => true,
            "entities" => catalog_entities.map { |entity| mapper.from_entity(entity) },
            "pages" => catalog_pages,
            "processing" => FlowchartDefinitions::Catalog.for_customer(@customer.id)
          }
        end

        # The workspace's own launched form pages, named the way
        # set_page_processing takes them.
        def catalog_pages
          pages = Page.where(customer_id: @customer.id, launched: true).joins(current_version: :content)
                      .where("#{Page::CONFIG_ENTITY_ID_SQL} IS NOT NULL").includes(:flowchart).order(:action_key).limit(CATALOG_PAGE_LIMIT).to_a
          Page.preload_entities(pages).select(&:entity).map do |page|
            { "action_key" => page.action_key, "name" => page.name, "audiences" => page.visible_audiences,
              "entity" => page.entity.name, "processing" => page.flowchart&.name }
          end
        end

        def catalog_entities
          Entity.where(customer_id: @customer.id).non_bridge.by_name.includes(current_version: :content)
        end

        def generate_page(entity_name)
          entity = Entity.where(customer_id: @customer.id, name: entity_name.to_s).first
          unless entity
            return {
              "ok" => false,
              "error" => I18n.t(
                "ai_assistant.assistant.apply_errors.target_not_found",
                name: entity_name
              )
            }
          end

          result = GeneratePage.call(entity: entity, customer: @customer)
          record_effect(result)
          {
            "ok" => result.ok,
            "skipped" => result.skipped,
            "message" => result.message,
            "page_name" => result.page&.name,
            "page_id" => result.page&.id
          }
        end

        def record_effect(result)
          return unless result.ok && result.page

          @effects << {
            kind: "page",
            action: result.created.present? ? "created" : "reused",
            record: result.page
          }
        end

        def verify_artifact(args)
          kind = args["kind"].to_s
          record = artifact_record(kind, args["id"])
          result = Verify.call(kind: kind, record: record, customer: @customer)
          { "ok" => result.ok, "issues" => result.issues }
        end

        def artifact_record(kind, id)
          return nil if kind == "flowchart" && !flowchart_visible?
          return nil if kind == "website_page" && !Artifact.website_enabled?(@customer)

          Artifact::MODELS[kind]&.where(customer_id: @customer.id)&.find_by(id: id)
        end

        def flowchart_visible?
          FlowchartVisibility.allowed?(@viewer)
        end
      end
    end
  end
end
