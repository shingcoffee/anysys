# frozen_string_literal: true

module CodeGenerators
  class PathIdentity
    def self.find(slug)
      GeneratorRegistry.all.find do |klass|
        klass.name.delete_prefix("CodeGenerators::").underscore == slug.to_s
      end
    end
  end
end
