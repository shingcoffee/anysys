# frozen_string_literal: true

module Pages
  # Composes an entity-backed page's configuration_json: populates the per-entity
  # field pages, applies an optional layout template, and resolves the theme
  # preset. Extracted from Admin::Maintenance::PagesController#create so the
  # controller action stays thin dispatch.
  #
  # Mutates the given page's configuration_json in place; a no-op unless the page
  # has an entity that yields at least one populated field page.
  class ConfigurationComposer
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(page:, template_key:, theme_preset_key:, entity: nil)
      @page = page
      @template_key = template_key
      @theme_preset_key = theme_preset_key
      @entity = entity
    end

    def call
      source = source_entity
      return unless source

      pages = PageFieldPopulator.call(source)
      return if pages.empty?

      config = page.configuration_json

      # A blank template defaults to "default" for entity-backed pages.
      effective_template_key = template_key.presence
      effective_template_key = "default" if effective_template_key.blank?

      if effective_template_key != "blank"
        pages = pages.map do |page_config|
          result = PageTemplateApplier.call(page_config["fields"], effective_template_key, entity: source)
          page_config.merge("fields" => flatten_template_fields(result[:fields]))
        end

        sample_result = PageTemplateApplier.call([], effective_template_key, entity: source)
        theme_key = theme_preset_key.presence || sample_result[:theme]
        config["theme"] = resolved_theme(theme_key, config) if theme_key.present?
        config["metadata"]["layout_template_key"] = effective_template_key
      elsif theme_preset_key.present?
        config["theme"] = resolved_theme(theme_preset_key, config)
      end

      config["pages"] = pages
      config.delete("fields")
      page.configuration_json = config
    end

    private

    attr_reader :page, :template_key, :theme_preset_key

    def source_entity
      @entity || page.entity
    end

    def resolved_theme(key, config)
      ThemeResolver::THEME_PRESETS[key] || config["theme"]
    end

    def flatten_template_fields(result_fields)
      return result_fields unless PageTemplateApplier.paginated_result?(result_fields)

      result_fields.flat_map { |p| p["fields"] || [] }
    end
  end
end
