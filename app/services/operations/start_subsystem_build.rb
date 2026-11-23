# frozen_string_literal: true

module Operations
  class StartSubsystemBuild < Base
    key "start_subsystem_build"
    version 2
    title "Start sub-system build"
    summary "Build a whole working sub-system from the requirements brief once you have analysed the real-world scenarios and the admin has answered your questions. A background build creates or reuses the domain, designs the business flows (the journeys people walk), designs the entities those flows need, builds a page for every journey step, writes the processing each submit needs, sets the pages to use it, launches the journeys that are ready, and reports back in this conversation. Do not call create_domain or create_entity for a sub-system you hand to this build. The build may ask the admin further questions in this conversation and leaves out anything that needs a password, token or secret. One build runs per conversation at a time."
    schema "start_subsystem_build.json"
    annotations destructive: false, confirmation: :never

    register!

    def validate(input)
      return [conversation_required] unless conversation
      return [build_active] if active_build?

      violations = actor_violations(input) + value_violations(input)
      return violations if violations.any?

      preflight_violations(input)
    end

    def plan(input)
      [{ "kind" => "subsystem_build", "action" => "started", "name" => brief(input).domain_name }]
    end

    def perform(input)
      return Outcome.invalid(operation: self.class.key, violations: [build_active]) if active_build?

      warnings = preflight(input).warnings.map(&:message)
      build = AiAssistant::SubsystemBuild.create!(
        customer_id: context.customer.id, conversation: conversation, user: context.actor,
        stage: AiAssistant::SubsystemBuild::STAGES.first,
        blueprint: { "domain" => brief(input).domain_name, "brief" => input },
        results: { "warnings" => warnings }
      )
      AiAssistant::SubsystemBuildJob.perform_later(build.id)

      Outcome.succeeded(
        operation: self.class.key,
        data: { "build" => build.id, "status" => build.status, "domain" => build.name, "warnings" => warnings },
        effects: plan(input)
      )
    end

    private

    def brief(input) = AiAssistant::Subsystems::Brief.new(input)

    def conversation
      found = context.conversation
      found if found && found.customer_id == context.customer.id
    end

    def active_build?
      AiAssistant::SubsystemBuild.unscoped.active.exists?(conversation_id: conversation.id)
    end

    def preflight(input)
      @preflight ||= AiAssistant::Subsystems::Preflight.call(
        customer: context.customer,
        plan: AiAssistant::Subsystems::Preflight::Plan.new(logins: brief(input).logins?, signup: brief(input).signup?)
      )
    end

    # Every scenario is started by one of the brief's people.
    def actor_violations(input)
      names = brief(input).people.map { |row| row["name"].to_s.squish }
      Array(input["scenarios"]).each_with_index.filter_map do |scenario, index|
        next if names.any? { |name| name.casecmp?(scenario["actor"].to_s.squish) }

        Violation.new(pointer: "/scenarios/#{index}/actor", code: "subsystem.actor_unknown",
                      details: { "actor" => scenario["actor"].to_s, "candidates" => Violation.candidates(scenario["actor"], names) })
      end
    end

    # A web or email address in the brief must be one the admin typed, so the
    # model can't hand the build an address it made up.
    def value_violations(input)
      screen = AiAssistant::Subsystems::Screen.for(conversation)
      brief(input).values.each_with_index.filter_map do |row, index|
        unknown = screen.unknown_text(row["value"].to_s)
        next if unknown.empty?

        Violation.new(pointer: "/values/#{index}/value", code: "subsystem.value_not_given", details: { "value" => unknown.first })
      end
    end

    def preflight_violations(input)
      preflight(input).blockers.map do |blocker|
        Violation.new(pointer: "/people", code: "subsystem.preflight_blocked", resolution: "blocked",
                      details: { "errors" => blocker.message })
      end
    end

    def conversation_required
      Violation.new(pointer: "", code: "subsystem.conversation_required", resolution: "blocked")
    end

    def build_active
      Violation.new(pointer: "", code: "subsystem.build_active", resolution: "blocked")
    end
  end
end
