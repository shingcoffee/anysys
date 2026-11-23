# frozen_string_literal: true

module AiAssistant
  module Subsystems
    # Works out each object's allowed status changes from the steps that make
    # them: the person walking the journey moves the record (status_to, or
    # the state they pick from status_choices), and a successful payment
    # moves it to paid_status on its own. Returns
    # { object name (downcased) => [{ "from", "to", "by" => [...] }] }.
    class Lifecycles
      SYSTEM = "system"

      def self.call(flows) = new(flows).call

      def initialize(flows)
        @flows = flows
        @moves = Hash.new { |hash, key| hash[key] = Hash.new { |inner, pair| inner[pair] = [] } }
      end

      def call
        @flows.journeys.each do |journey|
          after = {}
          @flows.steps(journey).each { |step| walk(journey, step, after) }
        end
        @moves.transform_values do |pairs|
          pairs.map { |(from, to), by| { "from" => from, "to" => to, "by" => by.uniq.sort } }
        end
      end

      private

      def walk(journey, step, after)
        object = @flows.object(step["object"]) or return
        status = @flows.status(object) or return
        before = states_before(journey, step, object, status, after)
        targets = targets(object, step)
        targets.each { |to| before.each { |from| move(object, from, to, @flows.audience(journey)) } }
        reached = targets.presence || before
        after[step["key"].to_s] = reached
        paid = canonical(object, step["paid_status"]) or return
        reached.each { |from| move(object, from, paid, SYSTEM) }
      end

      def states_before(journey, step, object, status, after)
        return [canonical(object, status["initial"])].compact if %w[create add].include?(step["kind"].to_s)

        key = step["edits"].to_s
        return after[key] if after.key?(key)

        listed = Array(@flows.start(journey)&.dig("status_in")).filter_map { |state| canonical(object, state) }
        listed.presence || @flows.states(object)
      end

      def targets(object, step)
        picks = Array(step["status_choices"]).filter_map { |state| canonical(object, state) }
        picks.presence || [canonical(object, step["status_to"])].compact
      end

      def move(object, from, to, by)
        return if from.blank? || to.blank? || Flows.same?(from, to)

        @moves[object["name"].to_s.squish.downcase][[from, to]] << by
      end

      # The state as the object spells it, so steps that write it in another
      # case still match.
      def canonical(object, state)
        return if state.to_s.strip.empty?

        @flows.states(object).find { |candidate| Flows.same?(candidate, state) }
      end
    end
  end
end
