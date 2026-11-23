# frozen_string_literal: true

module Journeys
  # Everything that must hold before a journey goes live: a valid definition,
  # a launched page per step and audience that adds records (the first one
  # because only a create submit starts a run), whose processing returns to
  # the journey rather than handing off to a module (only the last page step,
  # which finishes the run, may hand off: a checkout), every locked input filled
  # from an earlier step's record, and no other live journey starting on the
  # same page for the same audience. An update step's page instead edits
  # records, of the type the step it edits holds, and never for public
  # visitors, who have no record of their own. A journey started from a
  # record runs from that record's admin page or a member's own record page,
  # so it is for admins only or for members only (whose record type must then
  # be owned by a member), its record type must still be available with the
  # field its start condition reads, and only one live journey may start from
  # that record type on the same first page. A journey that opens by creating
  # a user runs on the admin users screen, so it is for admins only, the page
  # after it must save a person record, and only one live journey may open
  # that way for the same person page. A launched page always has live,
  # compatible processing (Page#launch_errors, PageProcessing), so that needs
  # no re-check here.
  class LaunchChecks
    ADMIN = EntityAttributeAudience::ADMIN
    MEMBER = EntityAttributeAudience::MEMBER
    PUBLIC = EntityAttributeAudience::PUBLIC
    RECORD_START_AUDIENCES = [[ADMIN], [MEMBER]].freeze

    def initialize(journey)
      @journey = journey
      @definition = journey.steps_definition
      @pages = {}
    end

    def errors
      return @definition.errors unless @definition.valid?
      return [t(:audiences_blank)] if @journey.visible_audiences.empty?

      (record_errors + user_errors + update_errors + step_errors + start_errors).uniq
    end

    private

    def record_errors
      record = @definition.record_start
      return [] unless record

      list = []
      list << t(:record_start_audience) unless RECORD_START_AUDIENCES.include?(@journey.visible_audiences)
      return list << t(:record_entity_missing) unless record_entity

      if @journey.visible_audiences == [MEMBER] && People::Ownership.kind(record_entity) != :owned
        list << t(:record_start_not_owned)
      end
      list << t(:record_when_field_missing) if record.when.is_a?(Hash) && !attribute?(record_entity, record.when["field"])
      list
    end

    def attribute?(entity, slug)
      Array(entity.property_schema_json).grep(Hash).any? { |attribute| attribute["name_slug"].to_s == slug.to_s }
    end

    def update_errors
      @journey.visible_to?(PUBLIC) && @definition.steps.any?(&:update?) ? [t(:update_not_public)] : []
    end

    def user_errors
      return [] unless @definition.user_start

      @journey.visible_audiences == [ADMIN] ? [] : [t(:user_start_admin_only)]
    end

    def record_entity
      return @record_entity if defined?(@record_entity)

      @record_entity = Entity.where(customer_id: [@journey.customer_id, nil]).active.non_bridge.find_by(id: @definition.record_start.entity_id)
    end

    def step_errors
      @definition.page_steps.flat_map do |step|
        @journey.visible_audiences.flat_map { |audience| page_errors(step, audience) }
      end
    end

    def page_errors(step, audience)
      page = page_for(step.action_key, audience)
      return [t(:page_missing, step: step.display_label, audience: audience_label(audience))] unless page
      if step.update?
        mode_errors = update_page_errors(step, page, audience)
        return mode_errors if mode_errors.any?
      elsif !page.serves?(:create)
        key = [@definition.first_step, @definition.account_step].include?(step) ? :start_not_create : :step_not_create
        return [t(key, step: step.display_label, audience: audience_label(audience))]
      end
      if !ends_journey?(step) && page.hands_off?(for_customer: @journey.customer)
        return [t(:step_hands_off, step: step.display_label, audience: audience_label(audience))]
      end
      if step == @definition.account_step && !page.entity&.person?
        return [t(:user_page_not_person, step: step.display_label)]
      end

      input_errors(step, page, audience)
    end

    # A step whose submit always finishes the run: nothing can follow it.
    def ends_journey?(step) = step == @definition.page_steps.last && !step.repeat

    # The page edits the record the step names, so it must take updates of
    # that record's type.
    def update_page_errors(step, page, audience)
      return [t(:step_not_update, step: step.display_label, audience: audience_label(audience))] unless page.serves?(:update)

      expected = source_entity_id(step.record, audience)
      return [] if expected.nil? || expected == page.entity_id.to_s

      [t(:update_entity_mismatch, step: step.display_label, audience: audience_label(audience))]
    end

    def input_errors(step, page, audience)
      declared = page.page_inputs
      unbound = declared.filter_map do |input|
        next if step.inputs[input["field"]].present?

        t(:input_unbound, step: step.display_label, audience: audience_label(audience), field: input_name(page, input["field"]))
      end
      mapped = step.inputs.filter_map do |field, from|
        declared_input = declared.find { |input| input["field"] == field }
        next t(:input_undeclared, step: step.display_label) unless declared_input

        t(:input_entity_mismatch, step: step.display_label) unless source_entity_id(from, audience) == declared_input["entity_id"]
      end
      unbound + mapped
    end

    # The record type an earlier step yields: the record start's own, or the
    # entity of that step's page for the audience.
    def source_entity_id(key, audience)
      source = @definition.step(key)
      return source.entity_id.to_s if source&.record?

      page_for(source&.action_key, audience)&.entity_id&.to_s
    end

    def input_name(page, slug)
      attribute = Array(page.entity&.property_schema_json).grep(Hash).find { |item| item["name_slug"] == slug }
      attribute&.dig("name").presence || slug.to_s.humanize
    end

    def start_errors
      clash = start_clashes.where.not(id: @journey.id).for_any_audience(@journey.visible_audiences).order(:id).first
      return [] unless clash

      [t(start_taken_key, name: clash.name)]
    end

    def start_taken_key
      return :record_start_taken if @definition.record_start
      return :user_start_taken if @definition.user_start

      :start_taken
    end

    def start_clashes
      live = Journey.launched.where(customer_id: @journey.customer_id)
      return live.opening_with_user_on(@definition.account_step.action_key) if @definition.user_start

      record = @definition.record_start
      return live.starting_on(@definition.first_step.action_key) unless record

      live.starting_from_record(record.entity_id, @definition.first_page_step.action_key)
    end

    def page_for(action_key, audience)
      return if action_key.blank?

      @pages.fetch([action_key, audience]) do |cache_key|
        @pages[cache_key] = Pages::ActionResolver.page_for(customer_id: @journey.customer_id, action_key: action_key, audience: audience)
      end
    end

    def audience_label(audience) = I18n.t("journeys.audiences.#{audience}")
    def t(key, **vars) = I18n.t("journeys.launch.errors.#{key}", **vars)
  end
end
