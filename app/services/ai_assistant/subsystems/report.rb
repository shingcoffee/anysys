# frozen_string_literal: true

module AiAssistant
  module Subsystems
    # The message a finished build posts: the entities it designed or reused,
    # what is live and what is still a draft and why, the form processing and
    # what the admin has to set up, what the build doesn't cover, and the
    # pre-check's notes.
    class Report
      def initialize(build:, results:)
        @build = build
        @results = results
      end

      def body
        AiAssistant::Assistant::Markdown.paragraphs(
          t("title", name: @build.name),
          section("entities", entity_lines),
          section("journeys", journey_lines),
          section("processing", processing_lines),
          section("not_covered", not_covered),
          section("warnings", Array(@results["warnings"]))
        )
      end

      private

      def flows = Flows.new(@results["flows"])

      def section(key, lines)
        ([t(key)] + lines.map { |line| "- #{line}" }).join("\n") if lines.any?
      end

      def entity_lines
        @results["entities"].to_h.values.compact.map do |row|
          t(row["created"] ? "entity_created" : "entity_reused", name: row["name"])
        end
      end

      def journey_lines
        flows.build_order.filter_map do |journey|
          key = journey["key"]
          row = @results.dig("journeys", key)
          next unless row
          next t("journey_failed", name: row["name"] || journey["name"], errors: joined(row["errors"])) if row["id"].nil?

          launch = @results.dig("launch", key) || {}
          case launch["status"]
          when "launched" then t("journey_launched", name: row["name"])
          when "live" then t("journey_live", name: row["name"])
          else t("journey_draft", name: row["name"], reasons: joined(launch["blockers"]))
          end
        end
      end

      def processing_lines
        Array(@results["needs"]).filter_map do |need|
          state = @results.dig("processing", need["name"])
          next unless state

          processing_line(need["name"], state)
        end
      end

      def processing_line(name, state)
        case state["status"]
        when "created"
          return t("processing_unbound", name: name, page: state["page"], errors: joined(state["errors"])) unless state["bound"]

          setup = Array(state["needs_setup"])
          return t("processing_bound", name: name, page: state["page"]) if setup.empty?

          t("processing_setup", name: name, page: state["page"], items: setup.join(t("separator")))
        when "skipped" then t("processing_skipped", name: name, items: joined(state["missing"]))
        else t("processing_failed", name: name, errors: joined(state["errors"]))
        end
      end

      def not_covered = (@build.brief.not_covered + flows.not_covered).uniq { |item| item.squish.downcase }

      def joined(list) = Array(list).map(&:to_s).reject(&:blank?).join(" ")

      def t(key, **) = I18n.t("ai_assistant.subsystems.report.#{key}", **)
    end
  end
end
