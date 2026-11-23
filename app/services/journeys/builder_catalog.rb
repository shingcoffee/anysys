# frozen_string_literal: true

module Journeys
  # The journey builder's view of its step pages: grouped by record type for
  # the page pickers (the journey's domain first, then other record types,
  # then pages bound to none), and per page what wiring a step needs — its
  # record type, audiences, whether it adds or edits records, and the record
  # fields it locks — plus the record types a journey can start from and the
  # choice fields (with their stored option values) a start condition can
  # check. A step names its page by action key, so a key's first page stands
  # for it, as in the step rows. Read-only views of what processing does:
  # each page's "On submit" summary (StepEffects), the other journeys that
  # pick up the records it leaves behind, and for each start-condition value
  # the steps of other journeys that leave records in it (Handoffs).
  class BuilderCatalog
    CHOICE_TYPES = Entities::EntryForm::CHOICE_TYPES

    Group = Data.define(:entity, :pages)
    Input = Data.define(:field, :entity_id, :label)
    Fit = Data.define(:entity_id, :entity_label, :audiences, :creates, :updates, :inputs)
    Choice = Data.define(:field, :label, :options)
    Option = Data.define(:value, :label, :sources) do
      def initialize(value:, label:, sources: "") = super
    end
    # A page's "On submit" lines and the journeys picking up its records;
    # +creating+ / +next_creating+ apply only when the step creates its record.
    Effects = Data.define(:flowchart, :lines, :creating, :next, :next_creating, :skips)

    attr_reader :pages, :customer_id

    def initialize(pages:, domain:, customer_id:, journey: nil)
      @pages = Page.preload_entities(Array(pages))
      ActiveRecord::Associations::Preloader.new(records: @pages, associations: :flowchart).call
      @domain = domain
      @customer_id = customer_id
      @journey = journey
    end

    def effects(page)
      @effects ||= {}
      @effects[page.id] ||= begin
        summary = step_effects.for(page)
        Effects.new(flowchart: summary.flowchart, lines: summary.lines, creating: summary.creating,
                    next: next_lines(summary.states), next_creating: next_lines(summary.initials - summary.states),
                    skips: summary.skips)
      end
    end

    def groups
      @groups ||= begin
        grouped = pages.group_by(&:entity)
        bound = grouped.keys.compact.sort_by { |entity| [domain_entity_ids.include?(entity.id) ? 0 : 1, entity.display_label.to_s.downcase, entity.id] }
        list = bound.map { |entity| Group.new(entity: entity, pages: grouped[entity]) }
        grouped.key?(nil) ? list << Group.new(entity: nil, pages: grouped[nil]) : list
      end
    end

    def fit(page)
      @fits ||= {}
      @fits[page.id] ||= Fit.new(
        entity_id: page.entity&.id&.to_s, entity_label: page.entity&.display_label.to_s,
        audiences: page.visible_audiences, creates: page.serves?(:create), updates: page.serves?(:update), inputs: inputs_of(page)
      )
    end

    def page_for(action_key)
      return if action_key.blank?

      pages.find { |page| page.action_key == action_key }
    end

    def entity_id_for(action_key)
      page = page_for(action_key)
      page && fit(page).entity_id
    end

    # The record types a journey can start from: the domain's first.
    def record_types
      @record_types ||= Entity.where(customer_id: [@customer_id, nil]).active.non_bridge.to_a.sort_by do |entity|
        [domain_entity_ids.include?(entity.id) ? 0 : 1, entity.display_label.to_s.downcase, entity.id]
      end
    end

    # Per record type id, its single- and multi-choice fields with fixed
    # options: what a record start's condition can check.
    def choices
      @choices ||= record_types.to_h { |entity| [entity.id.to_s, choices_of(entity)] }
    end

    private

    def customer = @customer ||= Customer.find(@customer_id)
    def step_effects = @step_effects ||= StepEffects.new(customer: customer)
    def handoffs = @handoffs ||= Handoffs.new(customer: customer, effects: step_effects)

    def next_lines(states)
      handoffs.next_for(states, except: @journey).map do |found|
        entity = entity_named(found.entity_id)
        lifecycle = Entities::Lifecycle.find(entity, found.field)
        I18n.t("journeys.admin.handoffs.next", journey: found.journey.name, audiences: audiences_text(found.journey),
                                               entity: entity&.display_label.to_s,
                                               states: StepEffects.join(found.values.map { |value| lifecycle ? lifecycle.label(value) : value }, last: :or))
      end
    end

    def sources_text(entity, field, value)
      list = handoffs.sources_for(entity.id, field, value, except: @journey).map do |source|
        I18n.t("journeys.admin.handoffs.source", journey: source.journey.name, step: source.step_name)
      end
      StepEffects.join(list)
    end

    def audiences_text(journey)
      StepEffects.join(journey.visible_audiences.map { |audience| I18n.t("journeys.audiences.#{audience}") })
    end

    def entity_named(entity_id)
      record_types.find { |entity| entity.id.to_s == entity_id.to_s } || referenced_entity(entity_id)
    end

    def referenced_entity(entity_id)
      @referenced_entities ||= {}
      @referenced_entities.fetch(entity_id.to_s) do
        @referenced_entities[entity_id.to_s] = Entity.where(customer_id: [@customer_id, nil]).find_by(id: entity_id)
      end
    end

    def domain_entity_ids
      @domain_entity_ids ||=
        @domain ? EntityDomainMembership.for_customer(@customer_id).where(entity_domain_id: @domain.id).pluck(:entity_id).to_set : Set.new
    end

    def inputs_of(page)
      schema = Array(page.entity&.property_schema_json).grep(Hash)
      page.page_inputs.map do |input|
        attribute = schema.find { |item| item["name_slug"] == input["field"] }
        Input.new(field: input["field"], entity_id: input["entity_id"],
                  label: attribute&.dig("name").presence || referenced_label(input["entity_id"]) || input["field"].humanize)
      end
    end

    def choices_of(entity)
      Array(entity.property_schema_json).grep(Hash).filter_map do |attribute|
        slug = attribute["name_slug"].to_s
        next unless CHOICE_TYPES.include?(attribute["html_type"]) && slug.match?(Definition::FIELD)
        next if Entities::ReferenceLabels.reference?(attribute) || attribute["type"] == Entity::ENTITY_REFERENCE_TYPE

        options = options_of(entity, slug, attribute)
        Choice.new(field: slug, label: attribute["display_label"].presence || attribute["name"].presence || slug, options: options) if options.any?
      end
    end

    def options_of(entity, slug, attribute)
      Array(attribute.dig("config", "options")).filter_map do |option|
        value = option.is_a?(Hash) ? option["value"] : option
        next unless (value.is_a?(String) || value.is_a?(Numeric)) && value.to_s.strip.present?

        label = option.is_a?(Hash) ? option["label"].to_s.presence : nil
        Option.new(value: value.to_s, label: label || value.to_s, sources: sources_text(entity, slug, value.to_s))
      end.uniq(&:value)
    end

    def referenced_label(entity_id)
      @referenced_labels ||= {}
      return @referenced_labels[entity_id] if @referenced_labels.key?(entity_id)

      @referenced_labels[entity_id] = Entity.where(customer_id: [@customer_id, nil]).find_by(id: entity_id)&.display_label.presence
    end
  end
end
