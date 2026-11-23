# frozen_string_literal: true

module Entities
  # The status lifecycle declared on an entity's choice attribute:
  #
  #   "lifecycle" => { "transitions" => [{ "from" => "submitted", "to" => "approved", "by" => ["admin"] }] }
  #
  # The states are the attribute's static option values and a new record
  # starts at the option marked default. Each transition lists who may cause
  # it: admin (the platform owner included), member, public, or system (a
  # write with no person behind it, such as a payment writeback).
  #
  # A lifecycle is in force only on a select or radio attribute with static
  # options, exactly one default option and at least one usable transition;
  # the entity operations refuse any other shape, and a transition naming a
  # state the options no longer have is ignored. Entries::Save checks every
  # write against it.
  class Lifecycle
    AUDIENCES = %w[admin member public system].freeze
    SYSTEM = "system"
    CHOICE_TYPES = %w[select radio].freeze
    DERIVED_TYPES = %w[Calculated Computed].freeze

    Transition = Data.define(:from, :to, :by)
    Violation = Data.define(:slug, :from, :to, :message)

    attr_reader :slug, :states, :initial, :transitions

    class << self
      # Every lifecycle in force on +entity+, in attribute order.
      def all(entity)
        Array(entity&.property_schema_json).filter_map { |attribute| from_attribute(attribute) }
      end

      def find(entity, slug)
        all(entity).find { |lifecycle| lifecycle.slug == slug.to_s }
      end

      # The states attribute +slug+ of an +entity+ record may move to from
      # +from+, optionally only those +audience+ may cause. A blank +from+ (a
      # new record) or one that is not a state starts at the initial state.
      def next_states(entity, slug, from, audience: nil)
        find(entity, slug)&.next_states(from, audience: audience) || []
      end

      # The lifecycle changes +entry+ is about to save that +audience+ may not cause.
      def violations(entry, audience:)
        audience = audience!(audience)
        lifecycles = all(entry.class.try(:bound_entity) || entry.entity)
        return [] if lifecycles.empty?

        before = entry.new_record? ? {} : stored_data(entry)
        after = entry.data_json
        lifecycles.filter_map do |lifecycle|
          lifecycle.check(before[lifecycle.slug], after[lifecycle.slug], audience: audience, new_record: entry.new_record?)
        end
      end

      def from_attribute(attribute)
        return unless attribute.is_a?(Hash) && attribute["lifecycle"].is_a?(Hash)
        return unless CHOICE_TYPES.include?(attribute["html_type"].to_s)
        return if DERIVED_TYPES.include?(attribute["type"].to_s)

        config = attribute["config"].is_a?(Hash) ? attribute["config"] : {}
        return unless static_options?(config)

        options = Array(config["options"]).grep(Hash)
        defaults = options.select { |option| [true, "true"].include?(option["default"]) }
        return unless defaults.one?

        labels = options.to_h { |option| [option_value(option), option["label"].to_s.strip.presence || option_value(option)] }
        labels.delete("")
        transitions = transitions_from(attribute["lifecycle"]["transitions"], labels.keys)
        return if transitions.empty?

        new(slug: attribute["name_slug"].to_s, labels: labels, initial: option_value(defaults.first), transitions: transitions)
      end

      # "owner" acts as admin; anything outside AUDIENCES is a caller bug.
      def audience!(value)
        audience = value.to_s == "owner" ? EntityAttributeAudience::ADMIN : value.to_s
        raise ArgumentError, "unknown lifecycle audience #{value.inspect}" unless AUDIENCES.include?(audience)

        audience
      end

      # Static options are stored as { "source" => "manual", "options" => [...] };
      # a constant or another entity's records fill the other choice lists.
      def static_options?(config)
        return false unless config["options_source"].to_s.in?(["", "manual"])
        return false if config["options_entity_name"].present? || config["entity_id"].present?
        return false if config["constant_id"].present? || config["constant_name"].present?

        config["source"].to_s.in?(["manual", ""]) && Array(config["options"]).grep(Hash).any?
      end

      def option_value(option)
        option["value"].to_s.strip.presence || option["label"].to_s.strip
      end

      private

      def transitions_from(rows, states)
        Array(rows).grep(Hash).filter_map do |row|
          from = row["from"].to_s.strip
          to = row["to"].to_s.strip
          by = Array(row["by"]).map(&:to_s) & AUDIENCES
          next unless states.include?(from) && states.include?(to) && from != to && by.any?

          Transition.new(from: from, to: to, by: by)
        end.uniq { |transition| [transition.from, transition.to] }
      end

      def stored_data(entry)
        raw = entry.attribute_in_database("data")
        value = raw.is_a?(String) ? JSON.parse(raw) : raw
        value.is_a?(Hash) ? value : {}
      rescue JSON::ParserError
        {}
      end
    end

    def initialize(slug:, labels:, initial:, transitions:)
      @slug = slug
      @labels = labels
      @states = labels.keys
      @initial = initial
      @transitions = transitions
    end

    def label(value)
      @labels.fetch(value.to_s, value.to_s)
    end

    def next_states(from, audience: nil)
      from = value_of(from)
      audience = self.class.audience!(audience) unless audience.nil?
      return [initial, *targets(initial, audience)].uniq unless states.include?(from)

      targets(from, audience)
    end

    def permits?(from, to, audience)
      transitions.any? { |transition| transition.from == from && transition.to == to && transition.by.include?(audience) }
    end

    # A new record may stay blank, start at the initial state, or take one
    # step from it. A saved record changes only along a transition; a blank or
    # unknown stored value counts as the initial state, and clearing a value
    # is refused. Returns nil when the change is allowed.
    def check(before, after, audience:, new_record:)
      before = value_of(before)
      after = value_of(after)
      return if new_record && after.empty?
      return if !new_record && after == before
      return refusal(before, after) if after.empty?

      known = states.include?(before)
      return if !known && after == initial
      return if permits?(known ? before : initial, after, audience)

      refusal(before.presence || initial, after)
    end

    private

    def targets(from, audience)
      transitions.select { |transition| transition.from == from && (audience.nil? || transition.by.include?(audience)) }
                 .map(&:to)
    end

    def value_of(value)
      value = value.first if value.is_a?(Array)
      value.to_s.strip
    end

    def refusal(from, to)
      message = if to.empty?
        I18n.t("maint_core.errors.validations.lifecycle_clear_refused", from: label(from))
      else
        I18n.t("maint_core.errors.validations.lifecycle_transition_refused", from: label(from), to: label(to))
      end
      Violation.new(slug: slug, from: from, to: to, message: message)
    end
  end
end
