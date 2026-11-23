# frozen_string_literal: true

module AiAssistant
  module Assistant
    # `@` mentions of existing artifacts in a chat message.
    #
    # Typing "@Invoice add a due date" names the subject of the turn outright,
    # which removes the round of "which entity did you mean?" that an
    # unqualified request otherwise costs.
    #
    # Names contain spaces ("Purchase Order"), so there is no delimiter that
    # could close a mention reliably. Instead the tenant's own artifact names
    # ARE the grammar: after each `@`, the longest catalog name the text starts
    # with wins. That keeps the message readable, works whether the admin
    # picked from the menu or typed it by hand, and cannot resolve to anything
    # the tenant does not already own.
    #
    # One service backs both directions — the composer's suggestion list and
    # the prompt's resolution — so the menu can never offer something the
    # parser would then fail to recognise.
    class Mentions
      SIGIL = "@"

      # Mentionable kinds, in menu order. Flowcharts are owner-only; Mentions.kinds_for
      # drops that key unless FlowchartVisibility.allowed?(viewer).
      MODELS = {
        "entity" => ->(customer_id) { Entity.where(customer_id: customer_id).non_bridge.by_name },
        "flowchart" => ->(customer_id) { Flowchart.where(customer_id: customer_id).by_name }
      }.freeze

      # A mention cannot run past the end of a word: "@Student" must not match
      # inside "@Students". The test is deliberately ASCII — Chinese runs
      # words together, so a following CJK character ends the name ("@发票加字段"
      # is a mention of 发票) while a following latin letter, digit or
      # underscore does not.
      NAME_BOUNDARY = /\A([^A-Za-z0-9_]|\z)/

      Candidate = Struct.new(:kind, :name, :label, keyword_init: true) do
        def as_json(*) = { "kind" => kind, "name" => name, "label" => label }
      end

      Mention = Struct.new(:kind, :record, keyword_init: true) do
        def name = record.name
      end

      class << self
        # Everything in this tenant the composer may offer.
        def candidates(customer_id:, viewer: nil)
          records_by_kind(customer_id: customer_id, viewer: viewer).flat_map do |kind, records|
            records.map { |record| Candidate.new(kind: kind, name: record.name, label: label_for(record)) }
          end
        end

        def kinds_for(viewer:)
          MODELS.keys.reject { |kind| kind == "flowchart" && !FlowchartVisibility.allowed?(viewer) }
        end

        # Artifacts named in `body`, in the order they appear, without repeats.
        # An unrecognised `@word` is simply prose and is left alone.
        def resolve(body:, customer_id:, viewer: nil)
          text = body.to_s
          return [] unless text.include?(SIGIL)

          index = index_by_name(customer_id: customer_id, viewer: viewer)
          return [] if index.empty?

          matched_names(text, index.keys).flat_map { |name| index.fetch(name) }
        end

        private

        def records_by_kind(customer_id:, viewer: nil)
          kinds_for(viewer: viewer).index_with { |kind| MODELS.fetch(kind).call(customer_id).to_a }
        end

        def index_by_name(customer_id:, viewer: nil)
          records_by_kind(customer_id: customer_id, viewer: viewer).each_with_object({}) do |(kind, records), index|
            records.each do |record|
              (index[record.name] ||= []) << Mention.new(kind: kind, record: record)
            end
          end.sort_by { |name, _| -name.length }.to_h
        end

        def matched_names(text, names)
          text.to_enum(:scan, SIGIL).filter_map { Regexp.last_match.end(0) }
              .filter_map { |offset| name_at(text, offset, names) }
              .uniq
        end

        def name_at(text, offset, names)
          remainder = text[offset..].to_s
          names.find do |name|
            remainder.downcase.start_with?(name.downcase) &&
              NAME_BOUNDARY.match?(remainder[name.length..].to_s)
          end
        end

        def label_for(record)
          return record.display_label if record.respond_to?(:display_label) && record.display_label.present?

          record.name
        end
      end
    end
  end
end
