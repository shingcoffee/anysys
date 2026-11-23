# frozen_string_literal: true

module CodeGenerators
  # Assembles the data needed to render the index/show page:
  # sidebar groupings, the client-side search index, and the filtered
  # generator list. All logic is pure (no HTTP / controller context);
  # the caller supplies the customer_id used to build absolute paths.
  class IndexPresenter
    def initialize(customer_id:, step_actions:, element_types:, category: nil, kind: nil, element_type: nil)
      @customer_id   = customer_id
      @step_actions  = step_actions
      @element_types = element_types
      @category      = category
      @kind          = kind
      @element_type  = element_type
    end

    # Returns an array of sidebar entry hashes.
    def sidebar_data
      sidebar = []

      @element_types.each do |name, _klass|
        sidebar << { kind: "element_type", key: name.to_s, label: name.to_s.titleize, count: 1 }
      end

      subcats = @step_actions.group_by { |_name, klass| klass._metadata[:category].to_s }
      subcats.each do |category, generators|
        sidebar << { kind: "step_action", key: category, label: category.tr("_", " ").titleize, count: generators.size }
      end

      sidebar
    end

    # Returns an array of search index entry hashes.
    def search_index
      index = []

      @element_types.each do |name, klass|
        relative = klass.name.delete_prefix("CodeGenerators::").underscore.gsub("::", "/")
        index << {
          name:        name.to_s,
          category:    klass._metadata[:category].to_s,
          description: klass._metadata[:description].to_s,
          kind:        "element_type",
          path:        generator_path(relative)
        }
      end

      @step_actions.each do |name, klass|
        relative = klass.name.delete_prefix("CodeGenerators::").underscore.gsub("::", "/")
        index << {
          name:        name.to_s,
          category:    klass._metadata[:category].to_s,
          description: klass._metadata[:description].to_s,
          kind:        "step_action",
          path:        generator_path(relative)
        }
      end

      index
    end

    # Returns the filtered subset of generators to display in the main panel.
    def filtered_generators
      if @element_type.present?
        gen = @element_types[@element_type]
        gen ? [[@element_type, gen]] : []
      elsif @category.present?
        @step_actions.select { |_name, klass| klass._metadata[:category].to_s == @category }.to_a
      else
        # Default: show first element type
        first_key = @element_types.keys.first
        first_key ? [[first_key, @element_types[first_key]]] : []
      end
    end

    private

    def generator_path(relative)
      "/#{@customer_id}/admin/maintenance/platform/code_generators/#{relative.gsub('/', '%2F')}"
    end
  end
end
