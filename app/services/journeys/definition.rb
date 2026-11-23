# frozen_string_literal: true

module Journeys
  # Parses and checks a journey's steps. Journeys are linear: a create step,
  # a record step (the existing record the journey is started from, on its
  # admin or member page), or a user step (an admin creates the sign-in
  # account on Authentication › Users › New, and the create step right after
  # it saves the person record linked to that account), then create, relate
  # or update steps in order, ending in exactly one finish step. A relate step
  # fills its page's locked inputs from earlier steps' records; an update
  # step's page edits the record an earlier step holds (its latest, when that
  # step repeated). An optional step may be skipped by the person, a
  # conditional one by an earlier step's processing (skip_journey_steps), and
  # so is every later step that needs its record (Journeys::Advance): the
  # journey only says which steps may be left out, the processing decides
  # when. A record step's `when` ({ "field", "in" }) offers the journey only
  # from records whose stored value for the field is listed
  # (Journeys::RecordStarts).
  class Definition
    KINDS = %w[create record user relate update finish].freeze
    START_KINDS = %w[create record user].freeze
    KEY = /\A[a-z][a-z0-9_]{0,39}\z/
    ID = /\A[1-9]\d*\z/
    FIELD = EntitySchemaValidation::ATTRIBUTE_SLUG_RE

    # `entity_id` is the record type of a record step, `when` its start
    # condition; `record` the earlier step whose record an update step edits;
    # `conditional` (true or nil) whether an earlier step's processing may
    # leave the step out.
    Step = Data.define(:key, :kind, :action_key, :label, :inputs, :repeat, :optional, :target, :entity_id, :record, :when,
                       :conditional) do
      def initialize(entity_id: nil, record: nil, when: nil, conditional: nil, **rest) = super

      def finish? = kind == "finish"
      def record? = kind == "record"
      def user? = kind == "user"
      def update? = kind == "update"
      def conditional? = conditional == true
      def page? = !finish? && !record? && !user?
      def display_label = label.presence || key

      # The earlier steps whose records this step can't run without.
      def needs = update? ? (inputs.values | [record.to_s]) : inputs.values

      # Whether a record start offers its journey from +entry+: no condition,
      # or the entry's stored value for the field (any of them, for a
      # multi-select) is listed. A malformed condition offers nothing.
      def admits?(entry)
        condition = self.when
        return true if condition.nil?
        return false unless condition.is_a?(Hash) && condition["in"].is_a?(Array) && entry

        listed = condition["in"].map(&:to_s)
        Array(entry.data_json.to_h[condition["field"].to_s]).any? { |value| listed.include?(value.to_s) }
      end
    end

    attr_reader :steps

    def self.blank = new("steps" => [])

    def initialize(raw)
      hash = raw.is_a?(String) ? parse(raw) : raw
      hash = hash.is_a?(Hash) ? hash.stringify_keys : {}
      @steps = Array(hash["steps"]).grep(Hash).map { |row| build(row.stringify_keys) }
    end

    def to_h = { "steps" => steps.map { |step| step.to_h.transform_keys(&:to_s).compact } }
    def step(key) = steps.find { |step| step.key == key.to_s }
    def first_step = steps.first
    def page_steps = steps.select(&:page?)
    def first_page_step = page_steps.first
    def record_start = (first_step if first_step&.record?)
    def user_start = (first_step if first_step&.user?)
    # The step whose new record is linked to the account a user start created.
    def account_step = (steps[1] if user_start && steps[1]&.page?)
    def progress_steps = steps.select { |step| step.page? || step.user? }
    def finish = steps.find(&:finish?)
    def finish_message = finish&.target.to_h["message"].to_s.strip.presence
    def action_keys = page_steps.map(&:action_key)
    def valid? = errors.empty?

    def next_after(key)
      index = steps.index { |step| step.key == key.to_s }
      index && steps[index + 1]
    end

    # Whether a run may pass the step without a record: it is optional or
    # conditional, or it needs the record of an earlier step that is.
    def skippable?(step) = skippable_keys.include?(step.key)

    def errors
      @errors ||= (structure_errors + steps.each_with_index.flat_map { |step, index| step_errors(step, index) }).uniq
    end

    private

    def parse(raw)
      JSON.parse(raw.presence || "{}")
    rescue JSON::ParserError
      {}
    end

    def build(row)
      Step.new(
        key: row["key"].to_s, kind: row["kind"].to_s, action_key: row["action_key"].to_s.presence,
        label: row["label"].to_s.strip.presence,
        inputs: row["inputs"].is_a?(Hash) ? row["inputs"].to_h { |field, from| [field.to_s, from.to_s] } : {},
        repeat: ActiveModel::Type::Boolean.new.cast(row["repeat"]) == true,
        optional: ActiveModel::Type::Boolean.new.cast(row["optional"]) == true,
        target: row["target"].is_a?(Hash) ? row["target"].stringify_keys : nil,
        entity_id: row["entity_id"].to_s.presence,
        record: row["record"].to_s.presence,
        when: row["when"].is_a?(Hash) ? row["when"].stringify_keys.slice("field", "in") : row["when"],
        conditional: (true if ActiveModel::Type::Boolean.new.cast(row["conditional"]) == true)
      )
    end

    def structure_errors
      list = []
      list << t(:too_short) if steps.size < 2
      list << t(:finish_last) unless steps.last&.finish? && steps.count(&:finish?) == 1
      list << t(:start_invalid) unless START_KINDS.include?(steps.first&.kind)
      list << t(:record_needs_page) if record_start && page_steps.empty?
      list << t(:user_needs_create) if user_start && account_step&.kind != "create"
      list << t(:duplicate_keys) if steps.map(&:key).uniq.size != steps.size
      list
    end

    def step_errors(step, index)
      list = []
      list << t(:key_invalid, step: step.display_label) unless step.key.match?(KEY)
      list << t(:kind_invalid, step: step.display_label) unless KINDS.include?(step.kind)
      list << t(:when_record_only, step: step.display_label) unless step.when.nil? || step.record?
      list << t(:conditional_page_only, step: step.display_label) if step.conditional? && !step.page?
      return list + finish_errors(step, index) if step.finish?
      return list + record_errors(step, index) if step.record?
      return list + user_errors(step, index) if step.user?

      earlier = record_sources(index).map(&:key)
      list << t(:action_key_invalid, step: step.display_label) unless step.action_key.to_s.match?(PageVisibility::ACTION_KEY)
      list << t(:repeat_relate_only, step: step.display_label) if step.repeat && step.kind != "relate"
      list << t(:optional_start, step: step.display_label) if step.optional && index.zero?
      list << t(:conditional_first, step: step.display_label) if step.conditional? && steps.first(index).none?(&:page?)
      list << t(:relate_needs_input, step: step.display_label) if step.kind == "relate" && step.inputs.empty?
      list << t(:input_source_invalid, step: step.display_label) if step.inputs.values.any? { |from| !earlier.include?(from) }
      list << t(:update_record_invalid, step: step.display_label) if step.update? && !earlier.include?(step.record.to_s)
      list
    end

    # The record is handed over when the journey starts, so the step has no
    # page and nothing to fill, repeat or skip.
    def record_errors(step, index)
      list = []
      list << t(:record_first_only, step: step.display_label) unless index.zero?
      list << t(:record_entity_invalid, step: step.display_label) unless step.entity_id.to_s.match?(ID)
      list + condition_errors(step)
    end

    def condition_errors(step)
      condition = step.when
      return [] if condition.nil?
      return [t(:when_field_invalid, step: step.display_label)] unless condition.is_a?(Hash) && condition["field"].is_a?(String) &&
                                                                       condition["field"].match?(FIELD)

      values = condition["in"]
      listed = values.is_a?(Array) && values.any? && values.all? { |value| value.is_a?(String) && value.strip.present? }
      listed ? [] : [t(:when_values_invalid, step: step.display_label)]
    end

    # The account is created on the users screen, not a page, and it is no
    # record: later steps can't fill from it or finish on it.
    def user_errors(step, index)
      index.zero? ? [] : [t(:user_first_only, step: step.display_label)]
    end

    def finish_errors(step, index)
      target = step.target.to_h
      case target["kind"]
      when "record"
        source = record_sources(index).find { |earlier| earlier.key == target["step"].to_s }
        return [t(:finish_record_invalid)] unless source

        skippable?(source) ? [t(:finish_record_optional)] : []
      when "page" then target["action_key"].to_s.match?(PageVisibility::ACTION_KEY) ? [] : [t(:finish_page_invalid)]
      else [t(:finish_target_invalid)]
      end
    end

    def record_sources(index) = steps.first(index).reject { |earlier| earlier.finish? || earlier.user? }

    def skippable_keys
      @skippable_keys ||= steps.each_with_object(Set.new) do |step, keys|
        keys << step.key if step.optional || step.conditional? || step.needs.any? { |from| keys.include?(from) }
      end
    end

    def t(key, **vars) = I18n.t("journeys.definition.errors.#{key}", **vars)
  end
end
