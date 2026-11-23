# frozen_string_literal: true

module AiAssistant
  module Subsystems
    # The processing a build writes, one per journey step whose submit does
    # more than save its record (Flows#processing?): its name, page, record
    # type and the purpose handed to AuthorProcessing. The purpose places the
    # page in its journey, says what the next step needs, and carries the
    # status move, the payment, the later steps it may leave out, the business
    # rules and what can go wrong.
    # Sign-up pages keep the sign-up processing.
    class ProcessingBrief
      NAME_LIMIT = 80
      KIND_PHRASES = { "create" => "creates a %<object>s", "add" => "adds %<object>s rows", "update" => "changes the %<object>s" }.freeze

      def self.needs(...) = new(...).needs

      # +entities+: { object name => { "id", "name" } }.
      def initialize(flows:, brief:, entities:)
        @flows = flows
        @brief = brief
        @entities = entities
      end

      def needs
        @flows.journeys.reject { |journey| @flows.public?(journey) }.flat_map do |journey|
          steps = @flows.steps(journey)
          steps.each_with_index.filter_map do |step, index|
            next unless @flows.processing?(step, journey)

            entity = @entities.find { |object, _row| Flows.same?(object, step["object"]) }&.last.to_h
            {
              "name" => "#{journey['name']}: #{step['label']}".squish.first(NAME_LIMIT), "journey" => journey["key"], "step" => step["key"],
              "audience" => @flows.audience(journey), "entity_id" => entity["id"], "entity" => entity["name"].to_s,
              "purpose" => purpose(journey, steps, index), "values" => Array(step["values"]).grep(Hash)
            }
          end
        end
      end

      private

      def purpose(journey, steps, index)
        step = steps[index]
        [
          "This page is step #{index + 1} of #{steps.size} of the journey \"#{journey['name']}\", walked by #{@flows.audience(journey)}; it #{phrase(step)}.",
          step["processing"].presence && "On submit: #{step['processing'].strip}",
          Array(step["system_fields"]).any? ? "Fields this processing fills: #{step['system_fields'].join(', ')}." : nil,
          status_line(step),
          payment_line(step),
          skip_line(journey, step),
          "Journey steps:\n#{steps.each_with_index.map { |row, at| "#{at + 1}. #{row['label']}: #{phrase(row)}#{' (this page)' if at == index}" }.join("\n")}",
          next_line(steps[index + 1]),
          list("Business rules", Array(@brief.to_h["rules"])),
          list("What can go wrong", Array(@brief.to_h["scenarios"]).grep(Hash).flat_map { |scenario| Array(scenario["exceptions"]) })
        ].compact.join("\n")
      end

      def phrase(step) = format(KIND_PHRASES.fetch(step["kind"].to_s, KIND_PHRASES["create"]), object: step["object"])

      def status_line(step)
        field = @flows.status(@flows.object(step["object"]))&.dig("field")
        return unless field

        if Array(step["status_choices"]).any?
          "Status: the person picks #{field} on the page (#{step['status_choices'].join(' or ')}); keep what they picked."
        elsif step["status_to"].present?
          "Status: set #{field} to #{step['status_to']} on this record (transition_state with no transitions follows the record's lifecycle)."
        end
      end

      def payment_line(step)
        return unless @flows.hands_off?(step)

        field = @flows.status(@flows.object(step["object"]))&.dig("field")
        "Payment: take the payment with request_payment on this record and put #{field} = #{step['paid_status']} in its paidFields, " \
          "so the status changes only once the payment succeeds. Never set it on submit."
      end

      # The later steps this submit may leave out, each behind its own decision.
      def skip_line(journey, step)
        rules = @flows.skipped_by(journey, step).map do |row|
          "- leave out \"#{row['label']}\" (step key #{row['key']}) when #{row.dig('skip', 'when').to_s.squish}"
        end
        return if rules.empty?

        "Later journey steps: decide from what this page saved, after it is saved, and use skip_journey_steps with the step key " \
          "only when the rule holds; otherwise do nothing, so the step runs.\n#{rules.join("\n")}"
      end

      def next_line(following)
        return "This is the journey's last page." unless following

        "Next page: \"#{following['label']}\", which #{phrase(following)} and shows #{Array(following['fields']).join(', ')}. " \
          "The records this page saves are carried to it automatically, so save everything it needs."
      end

      def list(title, items)
        items = items.map(&:to_s).reject(&:blank?)
        items.any? ? "#{title}:\n#{items.map { |item| "- #{item}" }.join("\n")}" : nil
      end
    end
  end
end
