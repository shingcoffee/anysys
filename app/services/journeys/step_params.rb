# frozen_string_literal: true

module Journeys
  # Turns the builder's start choice and step rows into a definition hash.
  # A journey started from an existing record begins with a record step for
  # the chosen record type (offered only from records whose chosen field
  # holds one of the chosen values, when a field is chosen), and one that
  # opens by creating a user account begins with a user step; otherwise, and
  # right after a user step, the first row creates (no inputs, no repeat,
  # never optional). After that a row the owner set to edit a record updates
  # the record of the earlier step it names (never repeats, may be skipped),
  # a page that locks records relates and one that locks nothing creates, and
  # the last row is the finish. Any later row may be marked as one an earlier
  # step's processing may leave out (`conditional`). A step names its page by id; the definition
  # stores the page's action key, so an unkeyed tenant page is given one here. Shared
  # pages are never written to: their key is global identity, owned by the
  # platform prefix, so an unkeyed shared page leaves the step without a key.
  module StepParams
    MESSAGE_LENGTH = 300
    RECORD_KEY = "record"
    USER_KEY = "user"
    UPDATE = "update"

    class << self
      def to_definition(rows, customer_id:, start: nil)
        list = normalize_rows(rows)
        lead = record_step(start) || user_step(start)
        steps = list.each_with_index.map do |row, index|
          key = row["key"].to_s.strip.presence || "step_#{index + 1}"
          next finish_step(row, key, customer_id) if index == list.size - 1

          step = page_step(row, key, index.zero? && lead&.dig("kind") != "record", customer_id)
          # No earlier page's processing runs before the first row.
          index.zero? ? step.except("conditional") : step
        end
        { "steps" => [lead, *steps].compact }
      end

      private

      def normalize_rows(rows)
        rows = rows.to_h if !rows.is_a?(Array) && rows.respond_to?(:to_h)
        (rows.is_a?(Hash) ? rows.values : Array(rows)).map { |row| stringify_row(row) }
      end

      def stringify_row(row)
        hash = row.respond_to?(:to_h) ? row.to_h : row
        hash.to_h.stringify_keys
      end

      def record_step(start)
        start = stringify_row(start) if start.respond_to?(:to_h)
        return unless start.is_a?(Hash) && start["kind"].to_s == "record"

        { "key" => start["key"].to_s.strip.presence || RECORD_KEY, "kind" => "record", "entity_id" => start["entity_id"].to_s.strip,
          "when" => condition(start["when"]) }.compact
      end

      # No field chosen means no condition; a field without values is kept so
      # the definition asks for one.
      def condition(raw)
        raw = stringify_row(raw) if raw.respond_to?(:to_h)
        return unless raw.is_a?(Hash)

        field = raw["field"].to_s.strip
        values = Array(raw["in"]).map { |value| value.to_s.strip }.compact_blank.uniq
        { "field" => field, "in" => values } if field.present?
      end

      def user_step(start)
        start = stringify_row(start) if start.respond_to?(:to_h)
        return unless start.is_a?(Hash) && start["kind"].to_s == "user"

        { "key" => start["key"].to_s.strip.presence || USER_KEY, "kind" => "user" }
      end

      def page_step(row, key, first, customer_id)
        page = find_page(row["page_id"], customer_id)
        return update_step(row, key, page, customer_id) if !first && row["kind"].to_s == UPDATE

        if first
          kind, inputs, repeat, optional, conditional = "create", {}, false, false, false
        else
          declared = page ? page.page_inputs.map { |input| input["field"] } : []
          inputs = row_inputs(row, declared)
          kind = declared.any? ? "relate" : "create"
          repeat = kind == "relate" && boolean(row["repeat"])
          optional = boolean(row["optional"])
          conditional = boolean(row["conditional"])
        end
        { "key" => key, "kind" => kind, "action_key" => page && action_key_for(page, customer_id),
          "label" => label(row), "inputs" => inputs, "repeat" => repeat, "optional" => optional,
          "conditional" => (true if conditional) }.compact
      end

      def update_step(row, key, page, customer_id)
        { "key" => key, "kind" => UPDATE, "action_key" => page && action_key_for(page, customer_id), "label" => label(row),
          "record" => row["record"].to_s.strip.presence, "optional" => boolean(row["optional"]),
          "conditional" => (true if boolean(row["conditional"])) }.compact
      end

      def finish_step(row, key, customer_id)
        message = row["finish_message"].to_s.strip.first(MESSAGE_LENGTH).presence
        target =
          case row["finish_kind"].to_s
          when "record" then { "kind" => "record", "step" => row["finish_step"].to_s, "message" => message }.compact
          when "page"
            page = find_page(row["finish_page_id"], customer_id)
            { "kind" => "page", "action_key" => page && action_key_for(page, customer_id), "message" => message }.compact
          end
        { "key" => key, "kind" => "finish", "label" => label(row), "target" => target }.compact
      end

      def row_inputs(row, declared)
        raw = row["inputs"]
        raw = raw.to_h if raw.respond_to?(:to_h)
        return {} unless raw.is_a?(Hash) && declared.any?

        raw.stringify_keys.slice(*declared).transform_values { |from| from.to_s.strip }.reject { |_, from| from.blank? }
      end

      def boolean(value) = ActiveModel::Type::Boolean.new.cast(value) == true

      def label(row) = row["label"].to_s.strip.presence

      def find_page(id, customer_id)
        Page.where(customer_id: [customer_id, nil]).find_by(id: id) if id.present?
      end

      def action_key_for(page, customer_id)
        return page.action_key if page.action_key.present?
        return if page.shared?

        key = unique_action_key(page, customer_id)
        page.update_columns(action_key: key)
        key
      end

      def unique_action_key(page, customer_id)
        slug = SectionSlug.for(page.name)
        base = slug.match?(/\A[a-z]/) ? slug : ["page", slug.presence].compact.join("_")
        (1..).lazy.map { |attempt| bounded(base, attempt == 1 ? "_#{page.id}" : "_#{page.id}_#{attempt}") }
             .find { |key| !Pages::ActionKeys.taken?(key, customer_id: customer_id) }
      end

      def bounded(base, suffix) = "#{base.first(63 - suffix.length)}#{suffix}"
    end
  end
end
