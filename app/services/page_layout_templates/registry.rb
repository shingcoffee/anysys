# frozen_string_literal: true

class PageLayoutTemplates
  class Registry
    TEMPLATE_DIR = File.expand_path("templates", __dir__).freeze

    class << self
      def all
        raw_all.map { |template| localize(template) }
      end

      def find(key)
        return nil if key.nil? || key.to_s.empty?

        template = raw_index[key.to_s]
        template && localize(template)
      end

      def keys
        all.map { |t| t[:key] }
      end

      def by_category
        all.group_by { |t| t[:category] }
      end

      def for_category(category)
        return all if category.nil? || category.to_s.empty? || category == "all"

        all.select { |t| t[:category] == category }
      end

      def category_counts
        counts = all.group_by { |t| t[:category] }.transform_values(&:length)
        counts["all"] = all.length
        counts
      end

      def reload!
        @raw_all = nil
        @raw_index = nil
      end

      private

      def raw_all
        @raw_all ||= load_templates.freeze
      end

      def raw_index
        @raw_index ||= raw_all.each_with_object({}) { |template, index| index[template[:key]] = template }
      end

      # Names and descriptions are catalog chrome. Translate at call time so a
      # memoized registry does not freeze the locale that first loaded it.
      # Preview-row sample labels stay in the template definition.
      def localize(template)
        key = template[:key]
        template.merge(
          name: I18n.t("layout_catalog.templates.#{key}.name", default: template[:name]),
          description: I18n.t("layout_catalog.templates.#{key}.description", default: template[:description])
        )
      end

      def load_templates
        Dir[File.join(TEMPLATE_DIR, "**/*.rb")].sort.each { |f| require f }

        definitions = collect_definitions(PageLayoutTemplates::Templates)
        sort_by_category_order(definitions)
      end

      def collect_definitions(mod)
        mod.constants.sort.flat_map do |const|
          child = mod.const_get(const)
          if child.is_a?(Module) && child.const_defined?(:DEFINITION)
            [child::DEFINITION]
          elsif child.is_a?(Module)
            collect_definitions(child)
          else
            []
          end
        end
      end

      def sort_by_category_order(definitions)
        category_order = PageLayoutTemplates::CATEGORY_ORDER
        definitions.sort_by do |t|
          [category_order.index(t[:category]) || 999, t[:key]]
        end
      end
    end
  end
end
