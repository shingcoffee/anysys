# frozen_string_literal: true

module AiAssistant
  module Subsystems
    # Read helpers over the business flows a build designed (schemas/flows.json):
    # the objects steps work on and the journeys people walk. Flows name
    # objects and fields the way people write them, so names compare
    # case-insensitively, ignoring repeated spaces.
    class Flows
      START = "start"
      RESERVED_KEYS = %w[start record user finish].freeze
      SCHEMA_PATH = Rails.root.join("app/services/ai_assistant/subsystems/schemas/flows.json")

      def self.same?(left, right) = left.to_s.squish.casecmp?(right.to_s.squish)
      def self.schema = @schema ||= JSON.parse(File.read(SCHEMA_PATH))

      # The stored attribute a flows field name stands for: by name, shown
      # label or the slug the name derives.
      def self.attribute(attributes, name)
        slug = EntityEntry.attribute_slug_for(name.to_s)
        Array(attributes).grep(Hash).find do |attribute|
          [attribute["name"], attribute["display_label"]].any? { |label| same?(label, name) } || attribute["name_slug"].to_s == slug
        end
      end

      # JSON Schema errors of +raw+ as plain sentences for the model.
      def self.schema_errors(raw)
        JSONSchemer.schema(schema).validate(raw).map do |error|
          pointer = error["data_pointer"].presence || "/"
          "#{pointer}: #{error['error']}"
        end.first(20)
      end

      def initialize(raw)
        @raw = raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
      end

      def to_h = @raw
      def objects = rows(@raw["objects"])
      def journeys = rows(@raw["journeys"])
      def not_covered = Array(@raw["not_covered"]).map(&:to_s).reject(&:blank?)

      def object(name) = objects.find { |row| same?(row["name"], name) }
      def journey(key) = journeys.find { |row| row["key"].to_s == key.to_s }
      def person = objects.find { |row| row["person"] == true }
      def status(object) = object.to_h["status"].is_a?(Hash) ? object["status"] : nil
      def states(object) = Array(status(object)&.dig("states")).map(&:to_s)
      def status_field?(object, name) = status(object).present? && same?(status(object)["field"], name)

      def steps(journey) = rows(journey.to_h["steps"])
      def start(journey) = journey.to_h["start"].is_a?(Hash) ? journey["start"] : nil
      def audience(journey) = journey.to_h["audience"].to_s
      def public?(journey) = audience(journey) == EntityAttributeAudience::PUBLIC

      # The object an earlier step's record (or the start record) is of.
      def source_object(journey, key)
        return object(start(journey)&.dig("object")) if key.to_s == START

        step = steps(journey).find { |row| row["key"].to_s == key.to_s }
        step && object(step["object"])
      end

      # A step's submit needs written processing when it does more than save
      # its record, when it changes the record's status itself, or when it
      # decides whether later steps of +journey+ are left out.
      def processing?(step, journey = nil)
        %w[processing status_to paid_status].any? { |key| step[key].to_s.strip.present? } || Array(step["system_fields"]).any? ||
          (journey.present? && skipped_by(journey, step).any?)
      end

      # The later steps of +journey+ whose skip rule +step+'s submit decides.
      def skipped_by(journey, step)
        steps(journey).select { |row| row["skip"].is_a?(Hash) && row["skip"]["by"].to_s == step["key"].to_s }
      end

      def hands_off?(step) = step["paid_status"].to_s.strip.present?

      # Sign-up journeys finish on the member journey they continue to, so
      # those are built first.
      def build_order = journeys.sort_by { |row| public?(row) ? 1 : 0 }

      def page_count = journeys.sum { |row| steps(row).size }

      # Every step that works on +object+, with its journey.
      def steps_on(object)
        journeys.flat_map { |journey| steps(journey).filter_map { |step| [journey, step] if same?(step["object"], object["name"]) } }
      end

      # The field names steps fill in on +object+, split by who fills them.
      def captured_fields(object)
        steps_on(object).flat_map { |_journey, step| Array(step["fields"]) }
                        .reject { |name| status_field?(object, name) }.uniq { |name| name.to_s.squish.downcase }
      end

      def system_fields(object)
        steps_on(object).flat_map { |_journey, step| Array(step["system_fields"]) }.uniq { |name| name.to_s.squish.downcase }
      end

      # Objects whose rows a step adds below +object+'s records.
      def children(object)
        journeys.flat_map do |journey|
          steps(journey).filter_map do |step|
            next unless step["kind"] == "add" && same?(source_object(journey, step["parent"])&.dig("name"), object["name"])

            object(step["object"])
          end
        end.compact.uniq { |row| row["name"].to_s.downcase }
      end

      # The parents +object+'s rows are added below.
      def parents(object)
        objects.select { |candidate| children(candidate).any? { |child| same?(child["name"], object["name"]) } }
      end

      # Objects members create or start journeys from, which must name the
      # member they belong to.
      def member_owned?(object)
        journeys.any? do |journey|
          next false unless audience(journey) == EntityAttributeAudience::MEMBER

          steps(journey).any? { |step| step["kind"] == "create" && same?(step["object"], object["name"]) } ||
            same?(start(journey)&.dig("object"), object["name"])
        end
      end

      private

      def rows(value) = Array(value).grep(Hash)
      def same?(left, right) = self.class.same?(left, right)
    end
  end
end
