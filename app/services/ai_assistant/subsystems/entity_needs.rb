# frozen_string_literal: true

module AiAssistant
  module Subsystems
    # What each business object of the flows needs from the entity designed
    # for it: the fields steps capture and processing fills, the record its
    # rows belong to, the member it belongs to, and its status lifecycle
    # worked out from the steps (Lifecycles).
    class EntityNeeds
      Need = Data.define(:name, :purpose, :person, :fields, :system_fields, :parents, :owned, :status, :transitions, :guarded) do
        def key = name.to_s.squish.downcase
        def logins? = person
      end

      def self.call(...) = new(...).call

      def initialize(flows:, brief:)
        @flows = flows
        @brief = brief
      end

      def call
        lifecycles = Lifecycles.call(@flows)
        @flows.objects.map do |object|
          person = object["person"] == true
          Need.new(
            name: object["name"].to_s.squish, purpose: object["purpose"].to_s, person: person,
            fields: @flows.captured_fields(object), system_fields: @flows.system_fields(object),
            parents: @flows.parents(object).map { |row| row["name"].to_s.squish },
            owned: !person && @flows.member_owned?(object),
            status: @flows.status(object), transitions: lifecycles.fetch(object["name"].to_s.squish.downcase, []),
            guarded: guarded_audiences(object)
          )
        end
      end

      # The prompt text describing +needs+ to the model, in its order.
      def self.describe(needs, person_model:, logins:)
        needs.map { |need| describe_one(need, needs, person_model, logins) }.join("\n\n")
      end

      def self.describe_one(need, needs, person_model, logins)
        person = needs.find(&:person)&.name
        lines = ["### #{need.name}", need.purpose]
        lines << "- Fields people fill in: #{need.fields.join(', ')}" if need.fields.any?
        if need.system_fields.any?
          read_only = need.guarded.map { |audience| "access.editable_by.#{audience} false" }.join(" and ")
          lines << "- Fields processing fills: #{need.system_fields.join(', ')}#{read_only.present? ? " (set #{read_only})" : ''}"
        end
        need.parents.each { |parent| lines << "- Its rows belong to a #{parent}: add a reference to #{parent} (options source entity_entries)." }
        lines << "- Each record belongs to one #{person}: add an owner reference to #{person} (owner true)." if need.owned && person
        if need.person && logins && person_model
          lines << "- These people sign in: extends #{person_model}; leave out the name and email fields it brings."
        end
        lines.concat(status_lines(need)) if need.status
        lines.join("\n")
      end

      def self.status_lines(need)
        status = need.status
        moves = need.transitions.map { |row| "#{row['from']} -> #{row['to']} by #{row['by'].join(', ')}" }
        [
          "- Status field \"#{status['field']}\" (select): states #{status['states'].join(', ')}; default option #{status['initial']}.",
          moves.any? ? "  lifecycle transitions: #{moves.join('; ')}" : "  no lifecycle (no step changes it)"
        ]
      end
      private_class_method :describe_one, :status_lines

      private

      # Members and visitors may not type values processing works out, so
      # those fields are read-only to the audiences whose pages save the object.
      def guarded_audiences(object)
        @flows.steps_on(object).map { |journey, _step| @flows.audience(journey) }.uniq - [EntityAttributeAudience::ADMIN]
      end
    end
  end
end
