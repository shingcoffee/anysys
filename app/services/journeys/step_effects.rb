# frozen_string_literal: true

module Journeys
  # What a step's page does when it is submitted, read from the processing
  # its tenant runs (the customer's override of a shared one included) and
  # from the page's own form: plain-language lines for the builder's "On
  # submit" block, the states the step can leave its record in (what
  # Journeys::Handoffs matches against record starts) and the later steps its
  # processing may leave out (skip_journey_steps). It only reports what the
  # processing does; deciding stays the processing's job.
  class StepEffects
    # A record state a submit can leave behind: +value+ of +field+ on an
    # +entity_id+ record.
    State = Data.define(:entity_id, :field, :value)

    # +lines+ apply to every submit, +creating+ only when the step creates its
    # record (as do +initials+, the states a new record starts in).
    Summary = Data.define(:flowchart, :lines, :creating, :states, :initials, :skips) do
      def processed? = !flowchart.nil?

      # The states a step leaves its record in: +creates+ when it creates one.
      def left_in(creates:) = creates ? (states | initials) : states
    end

    PAGE_RECORD = "model"
    SAVES = %w[new_model save_model upsert_model].freeze
    FILLS = %w[update_model set_record_fields].freeze
    MESSAGES = { "send_email" => :email, "send_template_email" => :email, "send_sms" => :sms,
                 "create_notification" => :notification, "send_chat_message" => :chat,
                 "send_webhook" => :webhook, "api_call" => :webhook }.freeze
    # Rules beyond the record's own field validation (validate_contract),
    # which every save applies.
    REFUSALS = %w[fail_with_error validate_value authorize authenticate].freeze
    OTHER_RECORD_OPERATIONS = %w[create update].freeze
    PERSON_AUDIENCES = (PageVisibility::AUDIENCES - [Entities::Lifecycle::SYSTEM]).freeze
    LITERAL = /\A\s*(?:"([^"\\]*)"|'([^'\\]*)')\s*\z/

    # "A, B and C" (+last+ :or: "A, B or C") in the current locale.
    def self.join(items, last: :and)
      items = items.uniq
      return items.first.to_s if items.size < 2

      separator = I18n.t("journeys.admin.effects.separators.list")
      "#{items[0...-1].join(separator)}#{I18n.t("journeys.admin.effects.separators.#{last}")}#{items.last}"
    end

    def initialize(customer:)
      @customer = customer
      @summaries = {}
      @flowcharts = {}
    end

    def for(page)
      @summaries[page.id] ||= Current.with_customer(@customer) { summarize(page) }
    end

    private

    def summarize(page)
      record = page.flowchart
      return Summary.new(flowchart: nil, lines: [t(:unprocessed)], creating: [], states: [], initials: [], skips: []) unless record

      flowchart = @flowcharts[record.id] ||= FlowchartRuntime::RuntimeFlowchart.new(record)
      Reading.new(page, flowchart).summary
    rescue JSON::ParserError
      Summary.new(flowchart: record, lines: [t(:unreadable)], creating: [], states: [], initials: [], skips: [])
    end

    def t(key, **vars) = I18n.t("journeys.admin.effects.#{key}", **vars)

    # One page's summary, built in the order its processing runs.
    class Reading
      def initialize(page, flowchart)
        @page = page
        @flowchart = flowchart
        @entity = page.entity
        @lifecycles = Entities::Lifecycle.all(@entity).index_by(&:slug)
        @lines = []
        @states = []
        @skips = []
        @saves = false
        @set_fields = Set.new
      end

      def summary
        @lines << t(:offline) unless @flowchart.launched?
        steps.each { |step| read(step["action"].to_s, step["config"].is_a?(Hash) ? step["config"] : {}) }
        form_choices
        lines = @lines.uniq
        lines = [t(:saves_only)] if lines == [t(:saves)]
        lines = [t(:nothing)] if lines.empty?
        creating, initials = starting_states
        Summary.new(flowchart: @flowchart.__getobj__, lines: lines, creating: creating, states: @states.uniq,
                    initials: initials, skips: @skips.uniq)
      end

      private

      def steps
        configuration = @flowchart.configuration_json
        elements = configuration.is_a?(Hash) ? Array(configuration["elements"]) : []
        elements.grep(Hash).flat_map do |element|
          properties = element["properties"]
          properties.is_a?(Hash) ? Array(properties["steps"]) : []
        end.grep(Hash)
      end

      def read(action, config)
        case action
        when *SAVES then saved
        when *FILLS then fill(config)
        when "transition_state" then transition(config)
        when "request_payment" then payment(config)
        when "hand_off_to_module" then @lines << t(:hand_off, module: module_name(config["moduleKey"]))
        when "skip_journey_steps" then skip(config)
        when "register_member" then @lines << t(:member_account)
        when "destroy_model" then @lines << t(config["mode"].to_s == "archive" ? :archives : :deletes)
        when "related_record", "child_records" then @lines << t(:other_records) if other_write?(config)
        when *MESSAGES.keys then @lines << t(MESSAGES.fetch(action))
        when *REFUSALS then @lines << t(:refuses)
        end
      end

      def saved
        @saves = true
        @lines << t(:saves)
      end

      def fill(config)
        return @lines << t(:other_records) unless page_record?(config["modelVariable"])

        pairs = Array(config["assignments"]).grep(Hash).filter_map do |pair|
          slug = pair["key"].to_s.strip
          [slug, pair["value"]] if slug.present?
        end
        moves, plain = pairs.partition { |slug, value| @lifecycles[slug]&.states&.include?(literal(value).to_s) }
        @set_fields.merge(pairs.map(&:first))
        @lines << t(:sets, fields: list(plain.map { |slug, _value| field_label(slug) })) if plain.any?
        moves.each { |slug, value| state_move(slug, literal(value)) }
      end

      def transition(config)
        return @lines << t(:other_records) if config["stateSource"].to_s == "variable" || !page_record?(config["modelVariable"])

        slug = config["stateField"].to_s.strip
        return if slug.empty?

        @set_fields << slug
        target = config["targetSource"].to_s == "variable" ? nil : config["targetState"].to_s.strip.presence
        state_move(slug, target) || @lines << t(:moves_computed, field: field_label(slug))
      end

      # A lifecycle field set to a known state; nil when +slug+ is no
      # lifecycle or +value+ is not one of its states.
      def state_move(slug, value, line: :moves)
        lifecycle = @lifecycles[slug]
        return unless lifecycle && lifecycle.states.include?(value.to_s)

        @states << State.new(entity_id: @entity.id.to_s, field: slug, value: value.to_s)
        @lines << t(line, field: field_label(slug), state: lifecycle.label(value))
      end

      def payment(config)
        @lines << t(:payment)
        return if config["paidRecord"].to_s.strip.present? && config["paidRecord"].to_s.strip != "ctx[:model]"

        Array(config["paidFields"]).grep(Hash).each do |pair|
          state_move(pair["key"].to_s.strip, pair["value"].to_s.strip, line: :paid_move)
        end
      end

      def skip(config)
        keys = Array(config["steps"]).map { |key| key.to_s.strip }.grep(Definition::KEY)
        @skips.concat(keys)
        @lines << t(:skips, steps: list(keys)) if keys.any?
      end

      def other_write?(config)
        config["operation"].nil? || OTHER_RECORD_OPERATIONS.include?(config["operation"].to_s)
      end

      # Lifecycle fields the page's form offers: people pick among the states
      # its audiences may move the record to.
      def form_choices
        return unless @entity

        audiences = @page.visible_audiences & PERSON_AUDIENCES
        (Pages::FormParams.primary_slugs(@page) & @lifecycles.keys).each do |slug|
          lifecycle = @lifecycles[slug]
          targets = lifecycle.transitions.select { |transition| transition.by.intersect?(audiences) }.map(&:to)
          targets |= [lifecycle.initial] if @page.serves?(:create)
          next if targets.empty?

          @set_fields << slug
          targets.each { |value| @states << State.new(entity_id: @entity.id.to_s, field: slug, value: value) }
          @lines << t(:chooses, field: field_label(slug), states: list(targets.map { |value| lifecycle.label(value) }, :or))
        end
      end

      # A record the step creates starts in each lifecycle's initial state,
      # unless the processing or the form sets that field.
      def starting_states
        return [[], []] unless @saves && @entity && @page.serves?(:create)

        @lifecycles.values.reject { |lifecycle| @set_fields.include?(lifecycle.slug) }.each_with_object([[], []]) do |lifecycle, (lines, states)|
          states << State.new(entity_id: @entity.id.to_s, field: lifecycle.slug, value: lifecycle.initial)
          lines << t(:starts_in, entity: @entity.display_label, field: field_label(lifecycle.slug),
                                 state: lifecycle.label(lifecycle.initial))
        end
      end

      def page_record?(variable)
        name = variable.to_s.strip.delete_prefix("ctx[:").delete_suffix("]")
        name.empty? || name == PAGE_RECORD
      end

      def literal(expression)
        match = LITERAL.match(expression.to_s)
        match && (match[1] || match[2])
      end

      def field_label(slug)
        attribute = Array(@entity&.property_schema_json).grep(Hash).find { |item| item["name_slug"] == slug }
        attribute&.dig("display_label").presence || attribute&.dig("name").presence || slug.to_s
      end

      def module_name(key)
        feature = FeatureModules::Module.find_by(key: key.to_s.strip)
        feature ? feature.display_name : key.to_s
      end

      def list(items, last = :and) = StepEffects.join(items, last: last)

      def t(key, **vars) = I18n.t("journeys.admin.effects.#{key}", **vars)
    end
  end
end
