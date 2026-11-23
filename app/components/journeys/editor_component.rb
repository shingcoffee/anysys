# frozen_string_literal: true

module Journeys
  # The owner's journey builder: the step timeline beside the journey's
  # details and launch readiness, saved from a sticky footer. The timeline
  # opens with where the journey starts (a new record, a new user account
  # and then its person record, or an existing record of a chosen type),
  # lists the page steps and ends in a fixed finish row;
  # each row's page decides whether it fills locked inputs from earlier steps
  # or the start record, unless the row is set to edit the record an earlier
  # step holds (StepParams). `preview_path` is the first step's page
  # with the draft preview key, or nil when there is no page to open yet.
  class EditorComponent < ApplicationComponent
    FORM_ID = "journey-form"
    STATUS_VARIANTS = ListComponent::STATUS_VARIANTS

    attr_reader :journey, :catalog, :domains, :errors

    def initialize(journey:, customer_id:, catalog:, domains:, errors: [], preview_path: nil, submitted_steps: nil,
                   submitted_start: nil, readiness: nil)
      @journey = journey
      @customer_id = customer_id
      @catalog = catalog
      @domains = Array(domains)
      @errors = Array(errors)
      @preview_path = preview_path
      @submitted_steps = Array(submitted_steps)
      @submitted_start = submitted_start&.to_h
      @readiness = readiness
    end

    def persisted? = journey.persisted?
    def title = persisted? ? journey.name_in_database.presence || t("journeys.admin.edit") : t("journeys.admin.new")
    def form_url
      persisted? ? helpers.admin_maintenance_journey_path(@customer_id, journey) : helpers.admin_maintenance_journeys_path(@customer_id)
    end

    def form_method = persisted? ? :patch : :post
    def new_page_path = helpers.new_admin_maintenance_page_path(@customer_id)
    def slugify? = !persisted?

    # The domain workspace the journey is listed on (the saved domain, so a
    # refused re-assignment still leads back to where it lives).
    def domain = domains.find { |candidate| candidate.id == journey.entity_domain_id_in_database } || journey.entity_domain
    def index_path = helpers.admin_maintenance_entities_path(@customer_id, domain_id: domain&.id)

    def breadcrumbs
      crumbs = [title]
      crumbs.unshift({ label: domain.name, path: index_path }) if domain
      helpers.definition_resource_breadcrumbs(:entities, *crumbs)
    end

    def badges
      return [] unless persisted?

      [{ label: t("journeys.admin.status.#{journey.status}"), variant: STATUS_VARIANTS.fetch(journey.status) }]
    end

    def actions
      list = []
      list << delete_action if persisted?
      list << duplicate_action if persisted?
      list << generate_action unless persisted?
      list << { label: t("journeys.admin.preview"), path: @preview_path, target: "_blank", rel: "noopener" } if @preview_path
      list << launch_action if persisted?
      list
    end

    def domain_options = domains.map { |domain| [domain.name, domain.id] }
    def audience_options = Journey::AUDIENCES.map { |audience| [t("journeys.audiences.#{audience}"), audience] }

    # A journey started from a record opens from that record's page, so it
    # has no start link.
    def start_url
      return unless persisted? && journey.launched? && record_step.nil?

      helpers.journey_start_url(customer_id: @customer_id, key: journey.key_in_database)
    end

    def record_start_note? = persisted? && journey.launched? && record_step.present?

    # A new journey starts with one page step and the finish.
    def page_steps
      @page_steps ||= definition_steps.select(&:page?).presence || [blank_step("create")]
    end

    def finish_step = definition_steps.find(&:finish?) || blank_step("finish")

    def submitted_step(index) = @submitted_steps[index] || {}
    def submitted_finish = @submitted_steps.size > page_steps.size ? @submitted_steps.last : {}

    def earlier_rows_for(index) = [record_source, *page_steps.first(index).each_with_index.map { |step, i| row_source(step, i) }].compact
    def page_row_sources = [record_source, *page_steps.each_with_index.map { |step, i| row_source(step, i) }].compact

    # The first page creates the journey's record unless it starts from one.
    def lead_row?(index) = index.zero? && !record_start?

    def start_kind
      kind = @submitted_start ? @submitted_start["kind"].to_s : lead_step&.kind || "create"
      StartStepComponent::KINDS.include?(kind) ? kind : StartStepComponent::KINDS.first
    end

    def record_start? = start_kind == "record"
    def start_entity_id = (@submitted_start ? @submitted_start["entity_id"] : record_step&.entity_id).to_s

    def start_key
      default = start_kind == "user" ? StepParams::USER_KEY : StepParams::RECORD_KEY
      (@submitted_start&.dig("key").presence || lead_step&.key).presence || default
    end

    def step_name_template = t("journeys.admin.step_number", number: "{number}")
    def record_name_template = t("journeys.admin.start.record_name", entity: "{entity}")
    def skipped_by_template = t("journeys.admin.step_conditional_by", steps: "{steps}")

    # Per-page wiring the builder controller uses to hint, switch mode, clone
    # fill pickers and show the "On submit" block when the owner chooses a page.
    def pages_payload
      catalog.pages.to_h do |page|
        fit = catalog.fit(page)
        [page.id.to_s, {
          "entity" => fit.entity_id,
          "updates" => fit.updates,
          "hint" => StepRowComponent.hint_for(fit),
          "inputs" => fit.inputs.map do |input|
            { "field" => input.field, "entity" => input.entity_id.to_s,
              "label" => t("journeys.admin.step_fill_from", field: input.label) }
          end,
          "effects" => StepEffectsComponent.payload(catalog, page, helpers.admin_maintenance_page_path(@customer_id, page))
        }]
      end
    end

    # Per record type, the choice fields and stored values a record start's
    # condition can check, with the other journeys' steps that leave records
    # in each value, for the builder to swap in when the type changes.
    def choices_payload
      catalog.choices.transform_values do |list|
        list.map do |choice|
          { "field" => choice.field, "label" => choice.label,
            "options" => choice.options.map do |option|
              { "value" => option.value, "label" => option.label, "sources" => StartStepComponent.reached_in(option.sources) }
            end }
        end
      end
    end

    def start_condition = @submitted_start ? @submitted_start["when"] : record_step&.when

    def readiness_issues = @readiness

    private

    def definition_steps = journey.steps_definition.steps
    def record_step = journey.steps_definition.record_start
    def lead_step = record_step || journey.steps_definition.user_start

    # The chosen start record, offered to the fill and finish pickers like an
    # earlier step.
    def record_source
      return unless record_start?

      entity = catalog.record_types.find { |candidate| candidate.id.to_s == start_entity_id }
      return unless entity

      { key: start_key, name: t("journeys.admin.start.record_name", entity: entity.display_label), entity_id: entity.id.to_s,
        optional: false, skips: [] }
    end

    # +optional+: the step may be passed without a record (skipped by the
    # person or by an earlier step's processing); +skips+: the later steps its
    # page's processing may leave out.
    def row_source(step, index)
      page = resolved_page(step, submitted_step(index))
      { key: StepRowComponent.key_for(step, index), name: step_name(step, index, page),
        entity_id: page && catalog.fit(page).entity_id, optional: step.optional || step.conditional?,
        skips: page ? catalog.effects(page).skips : [] }
    end

    def resolved_page(step, submitted)
      id = submitted["page_id"].to_s
      found = catalog.pages.find { |page| page.id.to_s == id } if id.present?
      found || catalog.page_for(step&.action_key)
    end

    def step_name(step, index, page)
      step.label.presence || page&.name || t("journeys.admin.step_number", number: index + 1)
    end

    def launch_action
      path = helpers.admin_maintenance_journey_launch_path(@customer_id, journey)
      if journey.launched?
        { label: t("journeys.admin.take_offline"), path: path, data: { turbo_method: :delete } }
      else
        { label: t("journeys.admin.launch"), path: path, data: { turbo_method: :post } }
      end
    end

    def delete_action
      { label: t("journeys.admin.delete"), path: helpers.admin_maintenance_journey_path(@customer_id, journey),
        variant: :ghost, icon: :trash, data: { turbo_method: :delete, turbo_confirm: t("journeys.admin.delete_confirm") } }
    end

    def duplicate_action
      { label: t("journeys.admin.duplicate"), path: helpers.admin_maintenance_journey_copy_path(@customer_id, journey),
        data: { turbo_method: :post } }
    end

    def generate_action
      { label: t("journeys.admin.generate"),
        path: helpers.generate_admin_maintenance_journeys_path(@customer_id, domain_id: journey.entity_domain_id) }
    end

    def blank_step(kind)
      Definition::Step.new(key: "", kind: kind, action_key: nil, label: nil, inputs: {}, repeat: false, optional: false, target: nil)
    end
  end
end
