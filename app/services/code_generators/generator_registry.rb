# frozen_string_literal: true

module CodeGenerators
  class GeneratorRegistry
    include Loggable

    class << self
      def instance
        @instance ||= new
      end

      delegate :find_step_action, :find_element_type, :all_generators,
               :step_action_generators, :element_type_generators, :reload!, to: :instance

      # Unique registered generator classes (step actions + element types).
      def all
        instance.all_generators.values.uniq
      end
    end

    def initialize
      @step_actions = {}
      @element_types = {}
      discover!
    end

    def find_step_action(action_name)
      @step_actions[action_name.to_s]
    end

    def find_element_type(type_name)
      @element_types[type_name.to_s]
    end

    def all_generators
      @step_actions.merge(@element_types)
    end

    def step_action_generators
      @step_actions.dup
    end

    def element_type_generators
      @element_types.dup
    end

    def reload!
      @step_actions.clear
      @element_types.clear
      discover!
    end

    private

    ELEMENT_TYPES_PATH = Rails.root.join("app/services/code_generators/element_types")
    PROCESS_PATH = ELEMENT_TYPES_PATH.join("process")
    SUPPORTED_ELEMENT_TYPES = %w[start end decision loop subflow].freeze

    def discover!
      # Scan element type generators (each type's own subfolder, excluding process/)
      ELEMENT_TYPES_PATH.children.select(&:directory?).each do |type_dir|
        next if type_dir.basename.to_s == "process"
        next unless SUPPORTED_ELEMENT_TYPES.include?(type_dir.basename.to_s)

        scan_directory(type_dir, @element_types)
      end

      # Scan step action generators (under process/<category>/)
      if PROCESS_PATH.exist?
        PROCESS_PATH.children.select(&:directory?).each do |category_dir|
          scan_directory(category_dir, @step_actions)
        end
      end
    end

    def scan_directory(dir, registry)
      return unless dir.exist?

      Dir[dir.join("**/*.rb")].each do |file|
        klass = class_from_file(file)
        next unless klass
        next unless klass.respond_to?(:registered_names)

        klass.registered_names.each do |name|
          if registry.key?(name) && registry[name] != klass
            log_warn(
              "Duplicate generator registration for #{name.inspect}: " \
              "#{registry[name].name} overridden by #{klass.name}"
            )
          end
          registry[name] = klass
        end
      end
    end

    def class_from_file(file)
      relative = Pathname.new(file).relative_path_from(Rails.root.join("app/services"))
      relative.to_s
              .delete_suffix(".rb")
              .camelize
              .constantize
    rescue NameError, LoadError => e
      # In development/test we must surface the failure loudly — a silently
      # absent generator is the root cause behind "step silently disappears
      # from the generated activity" bugs that can take hours to diagnose.
      # In production we log and keep the registry usable so the app boots.
      if defined?(Rails) && !Rails.env.production?
        raise
      else
        log_warn "Failed to load #{file}: #{e.class}: #{e.message}"
        nil
      end
    end
  end
end
