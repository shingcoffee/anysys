# frozen_string_literal: true

module Member
  # Pluggable contributor of Member::Surface descriptors. Concrete
  # subclasses live in Member::Sources::* and self-register via
  # `register!` at file load. The orchestrator that walks the registry is
  # Member::Surfaces.
  class SurfaceSource
    # ---- subclass interface (class methods) ----
    def self.key             ; raise NotImplementedError, "subclass must define .key"  ; end
    def self.name            ; raise NotImplementedError, "subclass must define .name" ; end
    def self.description     ; "" ; end
    def self.editable?       ; true ; end
    def self.position        ; 100 ; end

    def self.register!
      Member::Surfaces::SourceRegistry.register(self)
    end

    # ---- instance interface ----
    def initialize(customer:)
      @customer = customer
    end
    attr_reader :customer

    def surfaces
      raise NotImplementedError, "#{self.class} must define #surfaces"
    end

    def surface_for(key:)
      surfaces.find { |s| s.key.to_sym == key.to_sym }
    end
  end
end
