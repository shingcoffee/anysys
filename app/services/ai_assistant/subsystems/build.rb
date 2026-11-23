# frozen_string_literal: true

module AiAssistant
  module Subsystems
    # Runs a sub-system build from its stored stage:
    # - domain: creates or reuses the brief's business area;
    # - journeys: the model designs the business flows from the brief
    #   (AuthorFlows), and may ask the admin once;
    # - review: the platform owner approves the flows, or says what to
    #   change, before anything is built (tenant admins skip it);
    # - entities: the model designs the entities the flows need
    #   (AuthorEntities);
    # - pages: every journey's pages and draft journey (AssembleJourney);
    # - processing / binding: writes the processing each step needs and sets
    #   its page to use it;
    # - launch / report: launches what is ready and reports in the
    #   conversation.
    # Results are saved after every item, so a resumed or re-run build skips
    # what is done. It pauses with questions when it needs the admin and stops
    # as soon as the build is cancelled.
    class Build
      LOG_TAG = "[ai_assistant.subsystem_build]"
      STAGES = AiAssistant::SubsystemBuild::STAGES
      NEED_BUDGET = 4
      DONE = %w[created skipped failed].freeze

      def self.call(...) = new(...).call

      # +chat+: the completion callable for every model call; a
      # ProviderClient per call when nil.
      def initialize(build:, chat: nil)
        @build = build
        @chat = chat
        @results = build.results_json.deep_dup
      end

      def call
        return unless @build.running?
        return stop!("unauthorized") unless allowed?

        STAGES.drop(STAGES.index(@build.stage)).each do |stage|
          return unless checkpoint!(stage: stage)
          return if send(:"run_#{stage}") == :halt
        end
      rescue StandardError => e
        Rails.logger.error("#{LOG_TAG} build=#{@build.id} failed: #{e.class}: #{e.message}")
        stop!("unexpected")
      end

      private

      def run_domain
        return if domain

        found = EntityDomain.find_by_name(customer.id, brief.domain_name) || create_domain
        return stop!("domain_failed") unless found

        @results["domain_id"] = found.id
        nil
      end

      def create_domain
        customer.with_lock do
          result = EntityDomains::Activities::Save.call(
            domain: EntityDomain.new(customer_id: customer.id), customer_id: customer.id,
            params: { "name" => brief.domain_name, "description" => brief.domain_description.presence }.compact
          )
          result.model if result.success?
        end
      end

      def run_journeys
        return if @results["flows"].is_a?(Hash)

        result = AuthorFlows.call(build: @build, chat: chat(AuthorFlows::ATTEMPTS), may_ask: @results["flows_asked"] != true)
        case result.status
        when :flows then @results["flows"] = result.flows
        when :questions
          @results["flows_asked"] = true
          pause!(result.questions)
        else stop!("flows_failed")
        end
      end

      def run_review
        review = @results["review"] ||= {}
        return if review["status"] == "approved" || !Review.required?(@build)
        return ask_review(review) unless review["status"] == "asked"

        reply = AnswerHistory.replies(@build, 1).last&.last
        return ask_review(review) unless reply && Array(@build.answers).size > review["answers"].to_i

        if Review.approved?(reply.body)
          review.replace("status" => "approved")
          nil
        elsif Review.feedback(reply.body).casecmp?(Review.t("change"))
          ask_review(review)
        else
          revise(review, Review.feedback(reply.body))
        end
      end

      def revise(review, feedback)
        result = AuthorFlows.call(build: @build, chat: chat(AuthorFlows::ATTEMPTS), may_ask: false, feedback: feedback, previous: @results["flows"])
        return stop!("flows_failed") unless result.status == :flows

        @results["flows"] = result.flows
        ask_review(review)
      end

      def ask_review(review)
        review.replace("status" => "asked", "answers" => Array(@build.answers).size)
        pause!([Review.question], intro: Review.summary(flows, name: @build.name))
      end

      def run_entities
        return if @results["entities"].is_a?(Hash)

        blockers = preflight.blockers.map(&:message)
        return stop!("preflight", errors: blockers) if blockers.any?

        result = AuthorEntities.call(build: @build, flows: flows, chat: chat(AuthorEntities::ATTEMPTS))
        return stop!("entities", errors: result.errors) unless result.ok

        @results["entities"] = result.entities
        nil
      end

      def preflight
        fresh = flows.objects.count { |object| !Entity.where(customer_id: [customer.id, nil]).where("LOWER(name) = ?", object["name"].to_s.squish.downcase).exists? }
        Preflight.call(customer: customer,
                       plan: Preflight::Plan.new(entities: fresh, pages: flows.page_count, logins: brief.logins?, signup: brief.signup?))
      end

      def run_pages
        flows.build_order.each do |journey|
          next if journeys.key?(journey["key"])

          return :halt unless recorded { journeys[journey["key"]] = assemble(journey) }
        end
        @results["needs"] ||= ProcessingBrief.needs(flows: flows, brief: brief, entities: @results["entities"])
        nil
      end

      def assemble(journey)
        result = AssembleJourney.call(customer: customer, domain: domain, flows: flows, brief: brief, journey: journey,
                                      entities: @results["entities"], built: journeys)
        return { "name" => journey["name"], "errors" => result.errors } unless result.ok

        { "id" => result.journey.id, "name" => result.journey.name, "pages" => result.pages, "first_action_key" => result.first_action_key }
      end

      def run_processing
        questions = []
        needs.each do |need|
          state = processing[need["name"]] ||= {}
          next if DONE.include?(state["status"])

          author(need, state, questions)
          return :halt unless checkpoint!
        end
        pause!(questions) if questions.any?
      end

      def run_binding
        needs.each do |need|
          state = processing.fetch(need["name"], {})
          next unless state["status"] == "created" && !state.key?("bound")

          bind(need, state)
          return :halt unless checkpoint!
        end
        nil
      end

      def run_launch
        journeys.each do |key, row|
          next if row["id"].nil? || launches.key?(key)

          launches[key] = launch(key, row)
          return :halt unless checkpoint!
        end
        nil
      end

      def run_report
        message = nil
        @build.transaction do
          next unless finish!("finished")

          message = post(Report.new(build: @build, results: @results).body)
        end
        after_post(message) if message
        :halt
      end

      def customer = @build.customer
      def conversation = @build.conversation
      def brief = @build.brief
      def flows = Flows.new(@results["flows"])
      def needs = Array(@results["needs"])
      def journeys = @results["journeys"] ||= {}
      def processing = @results["processing"] ||= {}
      def launches = @results["launch"] ||= {}

      def domain
        @results["domain_id"] && EntityDomain.for_customer(customer.id).find_by(id: @results["domain_id"])
      end

      def allowed?
        user = @build.user
        return false unless user&.active?
        return false unless user.platform_owner? || (user.admin? && user.customer_id == customer.id)

        FeatureModules::Module.enabled?(key: AiAssistant::Activities::Preflight::MODULE_KEY, customer_id: customer.id) &&
          AiAssistant::ProviderSettings.active_for(:generation).present?
      end

      # The detailed binding reasons name flowcharts and their steps, which
      # only the platform owner sees.
      def owner_view? = FlowchartVisibility.allowed?(@build.user)

      def author(need, state, questions)
        page = target_page(need)
        return state.replace("status" => "failed", "errors" => [I18n.t("ai_assistant.subsystems.build.page_missing")]) unless page

        result = AuthorProcessing.call(build: @build, need: need, page: page, chat: chat(NEED_BUDGET), resumed: state["writing"] == true,
                                       before_write: -> { writing!(state) })
        case result.status
        when :created
          state.replace("status" => "created", "flowchart_id" => result.flowchart.id, "page" => page.name,
                        "needs_setup" => result.needs_setup)
        when :questions
          asked(need, state, result.questions, questions)
        else
          state.replace("status" => "failed", "page" => page.name, "errors" => result.errors)
        end
      end

      # Recorded just before the need's processing is written, so a re-run
      # after a worker died mid-write rewrites what it left in place.
      def writing!(state)
        state["writing"] = true
        checkpoint!
      end

      # One round of questions per need: asking again after the admin
      # answered leaves it out rather than looping.
      def asked(need, state, asked_now, questions)
        if state["status"] == "asking"
          return state.replace("status" => "skipped", "missing" => asked_now.map { |question| question["prompt"] })
        end

        state.replace("status" => "asking")
        questions.concat(asked_now.map do |question|
          question.merge("prompt" => I18n.t("ai_assistant.subsystems.build.question_prompt", name: need["name"], prompt: question["prompt"]))
        end)
      end

      def bind(need, state)
        page = target_page(need)
        flowchart = Flowchart.find_by(customer_id: customer.id, id: state["flowchart_id"])
        unless page && flowchart
          return state.merge!("bound" => false, "errors" => [I18n.t("ai_assistant.subsystems.build.page_missing")])
        end

        result = customer.with_lock { Pages::Activities::BindFlowchart.call(page: page, flowchart_id: flowchart.id) }
        state.merge!("bound" => result.ok, "page" => page.name)
        state["errors"] = owner_view? ? result.errors : result.reasons unless result.ok
      end

      def launch(key, row)
        journey = Journey.for_customer(customer.id).find_by(id: row["id"])
        return { "status" => "draft", "blockers" => [I18n.t("ai_assistant.subsystems.build.journey_unavailable")] } unless journey
        return { "status" => "live" } if journey.launched?

        blockers = launch_blockers(key)
        return { "status" => "draft", "blockers" => blockers } if blockers.any?

        result = customer.with_lock { Journeys::Activities::Launch.call(journey: journey) }
        result.ok ? { "status" => "launched" } : { "status" => "draft", "blockers" => Array(result.errors) }
      end

      def launch_blockers(key)
        waiting = needs.select { |need| need["journey"] == key && processing.dig(need["name"], "bound") != true }
        return [I18n.t("ai_assistant.subsystems.build.waiting_processing", names: waiting.map { |need| need["name"] }.join(", "))] if waiting.any?
        return [I18n.t("operations.journeys.sign_up_disabled")] if flows.public?(flows.journey(key)) && !signup_enabled?

        []
      end

      def signup_enabled? = Authentication::Settings.for(customer.id).signup_enabled?

      def target_page(need)
        id = journeys.dig(need["journey"], "pages", need["step"].to_s)
        page = id && Page.find_by(customer_id: customer.id, id: id)
        page if page && page.entity_id == need["entity_id"]
      end

      def chat(budget)
        @chat || AiAssistant::Assistant::ProviderClient.new(
          settings: AiAssistant::ProviderSettings.active_for(:generation), conversation: conversation, budget: budget
        ).method(:chat)
      end

      # An item's writes commit with the checkpoint recording them, so a
      # worker that dies in between leaves nothing a re-run doesn't know of.
      def recorded
        AiAssistant::SubsystemBuild.transaction do
          yield
          checkpoint! || raise(ActiveRecord::Rollback)
        end
      end

      # Every write is conditional on the build still running, so a cancel
      # that lands between two items is never overwritten.
      def checkpoint!(stage: @build.stage)
        changed = AiAssistant::SubsystemBuild.unscoped.where(id: @build.id, status: "running")
                                             .update_all(stage: stage, results: @results, updated_at: Time.current)
        mirror(stage: stage, results: @results)
        changed == 1
      end

      def finish!(status, questions: [])
        changed = AiAssistant::SubsystemBuild.unscoped.where(id: @build.id, status: "running")
                                             .update_all(status: status, questions: questions, results: @results, updated_at: Time.current)
        mirror(status: status, questions: questions, results: @results)
        changed == 1
      end

      # Keeps the loaded record equal to the row without marking it dirty, so
      # a later save of it doesn't skip or replay these columns.
      def mirror(**attributes)
        @build.assign_attributes(attributes.transform_values(&:deep_dup))
        @build.clear_attribute_changes(attributes.keys)
      end

      def pause!(questions, intro: nil)
        questions = AiAssistant::Assistant::Questions.sanitize(questions)
        message = nil
        @build.transaction do
          next unless finish!("waiting_for_answers", questions: questions)

          body = AiAssistant::Assistant::Markdown.paragraphs(intro, I18n.t("ai_assistant.subsystems.build.questions_intro", name: @build.name))
          message = post(body, "questions" => questions)
        end
        after_post(message) if message
        :halt
      end

      def stop!(reason, errors: [])
        @results["error"] = reason
        @results["errors"] = errors if errors.any?
        message = nil
        @build.transaction do
          next unless finish!("failed")

          message = post(AiAssistant::Assistant::Markdown.paragraphs(I18n.t("ai_assistant.subsystems.build.#{reason}", name: @build.name),
                                                                     errors.map { |error| "- #{error}" }.join("\n")))
        end
        after_post(message) if message
        :halt
      end

      def post(body, metadata = {})
        conversation.messages.create!(
          customer_id: customer.id, role: "assistant", status: "complete", body: body,
          metadata: metadata.merge("subsystem_build" => { "id" => @build.id })
        )
      end

      # Earlier build messages show the build's state and a Cancel button, so
      # they are re-rendered once it changes.
      def after_post(message)
        AiAssistant::Stream.broadcast_message(message)
        conversation.messages.where.not(id: message.id)
                    .where("json_extract(metadata, '$.subsystem_build.id') = ?", @build.id)
                    .find_each { |earlier| AiAssistant::Stream.broadcast_message_replace(earlier) }
      rescue StandardError => e
        Rails.logger.error("#{LOG_TAG} broadcast failed build=#{@build.id}: #{e.class}: #{e.message}")
      end
    end
  end
end
