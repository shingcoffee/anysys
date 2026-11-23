# frozen_string_literal: true

module Member
  module Surfaces
    # Registry of Member::SurfaceSource subclasses. Each source
    # self-registers via `register!` at file load.
    module SourceRegistry
      class << self
        def register(klass)
          @sources ||= {}
          @sources[klass.key.to_sym] = klass
        end

        def all
          (@sources || {}).values.sort_by(&:position)
        end

        def find(key)
          (@sources || {})[key.to_sym]
        end

        def reset!
          @sources = {}
        end
      end
    end
  end
end
