# frozen_string_literal: true

# Shared vendor-plugin registry behaviour, extracted from the four near-identical
# registries (Sms::Adapters, Email::Providers, Captcha::Providers,
# Payments::Gateways). A registry module extends the module returned by
# `PluginRegistry.build`:
#
#   module Sms::Adapters
#     extend PluginRegistry.build(label: "sms adapter", dir: "app/services/sms/adapters")
#   end
#
# Each concrete vendor file under `dir` calls `register!` (and optionally
# `default!`) in its class body. On first read the registry force-loads every
# file under `dir` (except `base.rb`) via `constantize`, so the single-file
# auto-discovery contract keeps working even where eager loading is off
# (dev/test). Pass `defaults: false` for registries with no default vendor
# (Payments), which omits `mark_default`/`default_key`.
module PluginRegistry
  def self.build(label:, dir:, defaults: true)
    Module.new do
      define_method(:register) { |klass| _plugins[klass.key.to_sym] = klass }

      define_method(:for) do |key|
        ensure_loaded!
        _plugins.fetch(key.to_sym) { raise ArgumentError, "unknown #{label}: #{key.inspect}" }
      end

      define_method(:keys) do
        ensure_loaded!
        _plugins.keys
      end

      define_method(:all) do
        ensure_loaded!
        _plugins.values
      end

      define_method(:ensure_loaded!) do
        return if @loaded

        Dir[Rails.root.join(dir, "*.rb")].each do |path|
          basename = File.basename(path, ".rb")
          next if basename == "base"

          "#{name}::#{basename.camelize}".constantize
        end
        # Only memoize after every file loaded — a raise above leaves the
        # registry unmemoized so the next call retries instead of serving a
        # silently partial plugin map for the life of the process.
        @loaded = true
      end

      define_method(:_plugins) { @registry ||= {} }
      private :_plugins

      next unless defaults

      define_method(:mark_default) { |klass| @default_key = klass.key.to_sym }

      define_method(:default_key) do
        ensure_loaded!
        @default_key || _plugins.keys.first ||
          raise("No #{label} registered — load #{dir}/*.rb")
      end
    end
  end
end
