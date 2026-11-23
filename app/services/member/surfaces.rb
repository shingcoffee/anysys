# frozen_string_literal: true

module Member
  # Customer-aware accessor over Member::SurfaceSource registry.
  # Member-facing API (.for, .fetch) is wire-compatible with the prior
  # version; new methods (.sources, .source_for, .surfaces_in) drive the
  # admin settings UI.
  module Surfaces
    class << self
      # Sorted list of registered SurfaceSource classes.
      def sources
        Surfaces::SourceRegistry.all
      end

      def source_for(key)
        Surfaces::SourceRegistry.find(key)
      end

      def for(customer:)
        descriptors_with_source = sources.flat_map { |klass|
          klass.new(customer: customer).surfaces.map { |d| [klass.key.to_sym, d] }
        }

        settings_by_key = SurfaceSetting.where(customer_id: customer.id)
                                        .index_by { |s| s.surface_key.to_sym }

        descriptors_with_source.map { |source_key, descriptor|
          EffectiveSurface.new(
            descriptor: descriptor,
            settings:   settings_by_key.fetch(descriptor.key) { NullSurfaceSetting.new },
            source_key: source_key
          )
        }.sort_by(&:position)
      end

      def fetch(key, customer:)
        found = self.for(customer: customer).find { |s| s.key.to_s == key.to_s }
        return found if found

        raise ActiveRecord::RecordNotFound, "no member surface for #{key.inspect}"
      end

      def surfaces_in(source_key:, customer:)
        self.for(customer: customer).select { |e| e.source_key == source_key.to_sym }
      end
    end
  end
end
