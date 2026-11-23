# frozen_string_literal: true

module AccessPoints
  module Registry
    @providers = []

    class << self
      def register(provider)
        @providers << provider
      end

      def providers
        @providers.dup
      end

      def applicable_for(customer_id:)
        @providers.select { |p| p.applicable?(customer_id: customer_id) }
      end

      def reset!
        @providers = []
      end

      # Registers the default provider set. Re-runnable; resets first.
      # Call after a `reset!` to restore the registry to its boot-time state.
      def install_default_providers!
        reset!
        register(RouteProvider.new)
        register(ModuleProvider.new)
        register(EntityClassProvider.new)
        register(EntityProvider.new)
        register(PageClassProvider.new)
        register(PageProvider.new)
        register(PlatformProvider.new)
      end
    end
  end
end
