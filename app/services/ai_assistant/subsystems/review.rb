# frozen_string_literal: true

module AiAssistant
  module Subsystems
    # The platform owner's one review of a build's flows before anything is
    # built: a summary of the journeys and one question whose answer either
    # approves them or says what to change. Tenant admins' builds go ahead
    # without it.
    module Review
      LOCALES = %i[en zh-CN].freeze
      AUDIENCES = EntityAttributeAudience::AUDIENCES

      module_function

      def required?(build) = build.user&.platform_owner? == true

      def question
        { "prompt" => t("question"), "type" => "single", "options" => [t("approve"), t("change")] }
      end

      # The admin's answer approves when it picks Build (in any locale) or
      # skips the questions; anything else they typed is the change to make.
      def approved?(body)
        answer = answer_of(body)
        approvals.any? { |text| text.casecmp?(answer) }
      end

      def feedback(body) = answer_of(body)

      def summary(flows, name:)
        lines = flows.journeys.map do |journey|
          steps = flows.steps(journey).each_with_index.map do |step, index|
            "#{index + 1}. #{t("steps.#{step['kind']}", label: step['label'], record: step['object'], fields: Array(step['fields']).join(t('separator')))}"
          end
          ["**#{journey['name']}** (#{t("audiences.#{flows.audience(journey)}")})", starts(flows, journey), *steps].compact.join("\n")
        end
        statuses = flows.objects.filter_map do |object|
          status = flows.status(object) or next
          "- #{t('status', record: object['name'], states: status['states'].join(t('separator')))}"
        end
        AiAssistant::Assistant::Markdown.paragraphs(
          t("intro", name: name), *lines, (statuses.any? ? [t("statuses"), *statuses].join("\n") : nil),
          (flows.not_covered.any? ? [t("not_covered"), *flows.not_covered.map { |item| "- #{item}" }].join("\n") : nil)
        )
      end

      def starts(flows, journey)
        start = flows.start(journey) or return
        states = Array(start["status_in"])
        return t("starts_any", record: start["object"]) if states.empty?

        t("starts", record: start["object"], states: states.join(t("separator")))
      end

      # The question card sends "prompt\nanswer"; a typed reply is all answer.
      def answer_of(body)
        first, rest = body.to_s.strip.split("\n", 2)
        prompts = LOCALES.map { |locale| I18n.with_locale(locale) { t("question") } }
        (prompts.any? { |prompt| prompt.casecmp?(first.to_s.strip) } ? rest : body).to_s.strip
      end

      def approvals
        LOCALES.flat_map do |locale|
          I18n.with_locale(locale) do
            [t("approve"), I18n.t("ai_assistant.assistant.questions.skip_reply"), I18n.t("ai_assistant.assistant.questions.no_preference")]
          end
        end
      end

      def t(key, **) = I18n.t("ai_assistant.subsystems.review.#{key}", **)
    end
  end
end
