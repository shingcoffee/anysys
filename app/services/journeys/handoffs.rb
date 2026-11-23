# frozen_string_literal: true

module Journeys
  # Which journeys pick up the records other journeys leave behind. A step
  # leaves its record in states (Journeys::StepEffects); a journey that
  # starts from a record with a start condition picks up records of that type
  # whose field holds one of the listed values. Read-only: the builder shows
  # the links under each step and on the start card, and the domain's
  # workflow map draws them.
  class Handoffs
    Pickup = Data.define(:journey, :entity_id, :field, :values) do
      def takes?(state) = state.entity_id == entity_id && state.field == field && values.include?(state.value)
    end
    Source = Data.define(:journey, :step, :page, :state) do
      def step_name = step.label.presence || page.name
    end
    Next = Data.define(:journey, :entity_id, :field, :values)
    Link = Data.define(:from, :to, :entity_id, :field, :values)

    attr_reader :journeys, :effects

    def initialize(customer:, journeys: nil, effects: nil)
      @customer = customer
      @journeys = journeys || ::Journey.for_customer(customer.id).by_name.to_a
      @effects = effects || StepEffects.new(customer: customer)
    end

    # The journeys that pick up a record left in +states+, other than +except+.
    def next_for(states, except: nil)
      pickups.filter_map do |pickup|
        next if except && pickup.journey.id == except.id

        values = states.select { |state| pickup.takes?(state) }.map(&:value).uniq
        Next.new(journey: pickup.journey, entity_id: pickup.entity_id, field: pickup.field, values: values) if values.any?
      end
    end

    # Where records of +entity_id+ get +field+ = +value+: journey steps other
    # than those of +except+.
    def sources_for(entity_id, field, value, except: nil)
      sources.select do |source|
        (except.nil? || source.journey.id != except.id) &&
          source.state.entity_id == entity_id.to_s && source.state.field == field.to_s && source.state.value == value.to_s
      end
    end

    # Journey-to-journey links: each journey to the others that pick up the
    # records its steps leave behind.
    def links
      sources.group_by(&:journey).flat_map do |journey, list|
        next_for(list.map(&:state), except: journey).map do |found|
          Link.new(from: journey, to: found.journey, entity_id: found.entity_id, field: found.field, values: found.values)
        end
      end
    end

    private

    def pickups
      @pickups ||= journeys.filter_map do |journey|
        start = definition_of(journey).record_start
        condition = start&.when
        next unless condition.is_a?(Hash) && condition["field"].present? && Array(condition["in"]).any?

        Pickup.new(journey: journey, entity_id: start.entity_id.to_s, field: condition["field"].to_s,
                   values: Array(condition["in"]).map(&:to_s))
      end
    end

    def sources
      @sources ||= journeys.flat_map do |journey|
        definition_of(journey).steps.flat_map do |step|
          page = step.page? && page_of(journey, step.action_key)
          next [] unless page

          @effects.for(page).left_in(creates: !step.update?).uniq.map do |state|
            Source.new(journey: journey, step: step, page: page, state: state)
          end
        end
      end
    end

    def definition_of(journey)
      @definitions ||= {}
      @definitions[journey.id] ||= journey.steps_definition
    end

    # A step's page for the journey's first audience that has one.
    def page_of(journey, action_key)
      return if action_key.blank?

      journey.visible_audiences.each do |audience|
        page = pages_for(audience)[action_key]
        return page if page
      end
      nil
    end

    # Every journey's step pages for one audience, resolved in one query.
    def pages_for(audience)
      @pages ||= {}
      @pages[audience] ||= begin
        keys = journeys.flat_map { |journey| definition_of(journey).page_steps.map(&:action_key) }
        found = Pages::ActionResolver.pages_for(customer_id: @customer.id, action_keys: keys, audience: audience)
        Page.preload_entities(found.values)
        ActiveRecord::Associations::Preloader.new(records: found.values, associations: :flowchart).call
        found
      end
    end
  end
end
