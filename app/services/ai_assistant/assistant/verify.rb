# frozen_string_literal: true

module AiAssistant
  module Assistant
    # Post-apply checks before the assistant claims the artifact is ready.
    class Verify
      Result = Struct.new(:ok, :issues, keyword_init: true) do
        def ok? = ok
      end

      def self.call(kind:, record:, customer:)
        new(kind: kind, record: record, customer: customer).call
      end

      def initialize(kind:, record:, customer:)
        @kind = kind.to_s
        @record = record
        @customer = customer
      end

      def call
        return failure(I18n.t("ai_assistant.assistant.verify.wrong_tenant")) if @record.blank? || @customer.blank?
        return failure(I18n.t("ai_assistant.assistant.verify.wrong_tenant")) unless @record.customer_id == @customer.id

        issues = case @kind
        when "entity" then entity_issues
        when "flowchart" then flowchart_issues
        when "page" then page_issues
        when "website_page" then website_page_issues
        else [I18n.t("ai_assistant.assistant.verify.unknown_kind", kind: @kind)]
        end
        Result.new(ok: issues.empty?, issues: issues)
      end

      private

      def failure(message)
        Result.new(ok: false, issues: [message])
      end

      def entity_issues
        return [] if @record.current_version.present?

        [I18n.t("ai_assistant.assistant.verify.entity_version_missing")]
      end

      def flowchart_issues
        config = @record.respond_to?(:configuration_json) ? @record.configuration_json : {}
        elements = Array(config.is_a?(Hash) ? config["elements"] : nil)
        issues = []
        unless elements.any? { |element| element.is_a?(Hash) && element["type"].to_s == "start" }
          issues << I18n.t("ai_assistant.assistant.apply_errors.flowchart_missing_start")
        end
        unless elements.any? { |element| element.is_a?(Hash) && element["type"].to_s == "end" }
          issues << I18n.t("ai_assistant.assistant.apply_errors.flowchart_missing_end")
        end
        issues
      end

      def website_page_issues
        sections = Array(@record.sections)
        return [I18n.t("ai_assistant.assistant.verify.website_page_empty")] if sections.empty?

        sections.filter_map do |section|
          type = section.is_a?(Hash) ? section["type"].to_s : ""
          next if Websites::SectionKit.known?(type)

          I18n.t("ai_assistant.assistant.verify.website_page_unknown_section", type: type)
        end
      end

      def page_issues
        config = @record.respond_to?(:configuration_json) ? @record.configuration_json : nil
        return [I18n.t("ai_assistant.assistant.verify.page_configuration_missing")] if config.blank?

        PageContentGenerator.new(@record).generate
        []
      rescue StandardError => e
        Rails.logger.warn("[AiAssistant::Verify] page render failed: #{e.class}: #{e.message}")
        [I18n.t("ai_assistant.assistant.verify.page_render_failed")]
      end
    end
  end
end
