# frozen_string_literal: true

module Admin
  module Maintenance
    class PageTemplateApplicationsController < PagesController
      def create
        @page = definition_scope(Page).find(params[:page_id])
        template_key = params[:template_key]

        if template_key.blank?
          render json: { error: t("maint_core.errors.page_templates.key_required") }, status: :unprocessable_entity
          return
        end

        template = PageLayoutTemplates.find(template_key)

        unless template
          render json: { error: t("maint_core.errors.page_templates.not_found") }, status: :not_found
          return
        end

        config = submitted_configuration
        unless config.is_a?(Hash)
          render json: { error: t("maint_core.errors.page_templates.invalid_configuration") }, status: :unprocessable_entity
          return
        end

        current_fields = Array(config["pages"]).flat_map { |page| page.is_a?(Hash) ? (page["fields"] || []) : [] }

        if current_fields.empty?
          render json: { error: t("maint_core.errors.page_templates.no_fields") }, status: :unprocessable_entity
          return
        end

        result = PageTemplateApplier.call(current_fields, template_key, entity: @page.entity)

        config["pages"] = if PageTemplateApplier.paginated_result?(result[:fields])
                            result[:fields]
        else
                            [{ "id" => "page_1", "name" => "Page 1", "order" => 1, "fields" => result[:fields] }]
        end
        config.delete("fields")

        if result[:theme].present?
          config["theme"] = ThemeResolver::THEME_PRESETS[result[:theme]] || config["theme"]
        end

        config["metadata"] ||= {}
        config["metadata"]["layout_template_key"] = template_key

        render json: { success: true, configuration: config, template_layout: template[:layout] }
      end

      private

      def submitted_configuration
        raw = params[:configuration]
        return @page.configuration_json if raw.blank?

        parsed = case raw
                 when String then JSON.parse(raw)
                 when ActionController::Parameters then raw.to_unsafe_h
                 else raw
                 end
        parsed
      rescue JSON::ParserError, TypeError
        nil
      end
    end
  end
end
