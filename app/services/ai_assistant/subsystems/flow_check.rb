# frozen_string_literal: true

module AiAssistant
  module Subsystems
    # Cross-field rules the flows schema cannot express. Returns plain English
    # problems that go back to the model so it can repair its flows; an empty
    # list means the flows can be built.
    class FlowCheck
      def self.call(flows:, brief:) = new(flows:, brief:).call

      def initialize(flows:, brief:)
        @flows = flows
        @brief = brief
        @problems = []
      end

      def call
        check_objects
        check_journeys
        @problems.uniq
      end

      private

      def check_objects
        duplicates(@flows.objects.map { |row| row["name"].to_s.squish.downcase }).each { |name| add("Object #{name} is listed twice.") }
        add("Only one object can be the person.") if @flows.objects.count { |row| row["person"] == true } > 1
        @flows.objects.each { |object| check_status(object) }
      end

      def check_status(object)
        status = @flows.status(object) or return
        states = @flows.states(object)
        add("#{object['name']}: initial #{status['initial']} is not one of its states.") unless includes?(states, status["initial"])
      end

      def check_journeys
        duplicates(@flows.journeys.map { |row| row["key"].to_s }).each { |key| add("Journey key #{key} is used twice.") }
        @flows.journeys.each do |journey|
          check_audience(journey)
          check_start(journey)
          check_steps(journey)
        end
      end

      def check_audience(journey)
        label = "Journey #{journey['key']}"
        case @flows.audience(journey)
        when EntityAttributeAudience::MEMBER
          add("#{label}: member journeys need people who sign in; the brief says they never do.") unless @brief.logins?
          add("#{label}: member journeys need a person object.") unless @flows.person
        when EntityAttributeAudience::PUBLIC then check_public(journey, label)
        end
        add("#{label}: only public sign-up journeys continue to another journey.") if journey["continues_to"].present? && !@flows.public?(journey)
      end

      def check_public(journey, label)
        steps = @flows.steps(journey)
        add("#{label}: public journeys only sign people up, so the brief must allow sign-up.") unless @brief.signup?
        add("#{label}: a public journey never starts from an existing record.") if @flows.start(journey)
        unless steps.first && steps.first["kind"] == "create" && same?(steps.first["object"], @flows.person&.dig("name"))
          add("#{label}: a public journey's first step creates the person object.")
        end
        target = journey["continues_to"].presence or return
        continued = @flows.journey(target)
        return add("#{label}: continues_to #{target} is not a member journey.") unless continued && @flows.audience(continued) == EntityAttributeAudience::MEMBER

        add("#{label}: continues_to #{target} starts from an existing record, so a new member can't continue on it.") if @flows.start(continued)
      end

      def check_start(journey)
        start = @flows.start(journey) or return
        object = @flows.object(start["object"])
        return add("Journey #{journey['key']}: start object #{start['object']} is not in objects.") unless object
        if object["person"] == true && @flows.audience(journey) == EntityAttributeAudience::MEMBER
          add("Journey #{journey['key']}: members change their own details on their profile, so a member journey can't start from the person object.")
        end

        Array(start["status_in"]).reject { |state| includes?(@flows.states(object), state) }.each do |state|
          add("Journey #{journey['key']}: #{state} is not a state of #{object['name']}.")
        end
      end

      def check_steps(journey)
        steps = @flows.steps(journey)
        duplicates(steps.map { |row| row["key"].to_s }).each { |key| add("Journey #{journey['key']}: step key #{key} is used twice.") }
        steps.each_with_index do |step, index|
          label = "Journey #{journey['key']} step #{step['key']}"
          add("#{label}: #{step['key']} is a reserved key.") if Flows::RESERVED_KEYS.include?(step["key"].to_s)
          object = @flows.object(step["object"])
          next add("#{label}: object #{step['object']} is not in objects.") unless object

          add("#{label}: the first step can't be optional.") if index.zero? && step["optional"] == true
          check_first_step(journey, step, label) if index.zero?
          check_skip(journey, step, steps.first(index), label)
          check_source(journey, step, steps.first(index), object, label)
          check_status_moves(journey, step, object, label, steps.drop(index + 1))
        end
      end

      def check_first_step(journey, step, label)
        if @flows.start(journey)
          add("#{label}: a journey with a start record begins by adding to or updating it.") if step["kind"] == "create"
        elsif step["kind"] != "create"
          add("#{label}: a journey without a start record begins with a create step.")
        end
      end

      def check_skip(journey, step, earlier, label)
        skip = step["skip"] or return
        return add("#{label}: the first step can't be skipped.") if earlier.empty?

        by = earlier.find { |row| row["key"].to_s == skip["by"].to_s }
        return add("#{label}: skip by #{skip['by']} is not an earlier step.") unless by

        add("#{label}: a public sign-up step can't decide which steps are skipped.") if @flows.public?(journey)
      end

      def check_source(journey, step, earlier, object, label)
        reference = { "add" => "parent", "update" => "edits" }[step["kind"].to_s] or return
        key = step[reference].to_s
        return add("#{label}: #{step['kind']} steps need #{reference}.") if key.blank?

        known = (@flows.start(journey) ? [Flows::START] : []) + earlier.map { |row| row["key"].to_s }
        return add("#{label}: #{reference} #{key} is not the start record or an earlier step.") unless known.include?(key)

        source = @flows.source_object(journey, key)
        if step["kind"] == "update" && !same?(source&.dig("name"), object["name"])
          add("#{label}: it updates #{object['name']} but #{key} is a #{source&.dig('name')}.")
        elsif step["kind"] == "add" && same?(source&.dig("name"), object["name"])
          add("#{label}: rows can't belong to a record of the same object.")
        end
      end

      def check_status_moves(journey, step, object, label, later)
        states = @flows.states(object)
        moves = [step["status_to"], step["paid_status"], *Array(step["status_choices"])].map(&:to_s).reject(&:blank?)
        return add("#{label}: #{object['name']} has no status, so the step can't change it.") if moves.any? && states.empty?

        moves.reject { |state| includes?(states, state) }.each { |state| add("#{label}: #{state} is not a state of #{object['name']}.") }
        picks = Array(step["fields"]).any? { |name| @flows.status_field?(object, name) }
        add("#{label}: the status field is in fields, so list the states people may pick in status_choices.") if picks && Array(step["status_choices"]).empty?
        add("#{label}: status_choices need the status field in fields.") if !picks && Array(step["status_choices"]).any?
        add("#{label}: a step that takes a payment ends its journey.") if @flows.hands_off?(step) && later.any?
        add("#{label}: public sign-up steps can't take a payment.") if @flows.hands_off?(step) && @flows.public?(journey)
      end

      def includes?(states, state) = states.any? { |candidate| same?(candidate, state) }
      def same?(left, right) = Flows.same?(left, right)
      def duplicates(list) = list.tally.select { |_value, count| count > 1 }.keys
      def add(message) = @problems << message
    end
  end
end
