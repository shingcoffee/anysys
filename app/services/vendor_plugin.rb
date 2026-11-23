# frozen_string_literal: true

# Shared surface for the three vendor plugin base classes (Sms::Adapters::Base,
# Email::Providers::Base, Captcha::Providers::Base), which duplicated the same
# identity/i18n class methods and a one-line injected-object initializer.
#
# `include` the module returned by `VendorPlugin.mixin` in the base class body:
#
#   class Base
#     include VendorPlugin.mixin(
#       i18n_prefix: "sms.adapters",
#       registry:    Sms::Adapters,
#       inject:      :credential,
#       credential_fallback: ->(name) { I18n.t("sms.credentials.#{name}", default: name.to_s.humanize) }
#     )
#     # ... vendor-specific class methods (delivery_mechanism, …) and the
#     #     send/query/verify instance interface stay here.
#   end
#
# It provides, on the class:
#   key / default_display_name  — abstract, raise NotImplementedError
#   display_name / field_label / credential_label — call-time I18n under
#     `i18n_prefix`, with `credential_fallback` for unkeyed credential labels
#   config_fields (=> []) / configured?(_) (=> false)
#   register! / default!        — into `registry`
# and, on instances, `initialize(<inject>:)` storing the injected object behind a
# protected reader. The injected object differs by domain (a Credential for
# sms/email, a ProviderSettings for captcha), so its name is threaded via `inject`.
module VendorPlugin
  def self.mixin(i18n_prefix:, registry:, inject:, credential_fallback:)
    class_methods = Module.new do
      define_method(:key) { raise NotImplementedError, "#{name} must declare .key" }

      define_method(:default_display_name) do
        raise NotImplementedError, "#{name} must declare .default_display_name"
      end

      define_method(:display_name) do
        I18n.t("#{i18n_prefix}.#{key}.name", default: default_display_name)
      end

      define_method(:config_fields) { [] }

      define_method(:field_label) do |field|
        I18n.t("#{i18n_prefix}.#{key}.fields.#{field[:name]}", default: field[:label].to_s)
      end

      define_method(:credential_label) do |name|
        I18n.t("#{i18n_prefix}.#{key}.credentials.#{name}", default: credential_fallback.call(name))
      end

      define_method(:configured?) { |_injected| false }

      define_method(:register!) { registry.register(self) }
      define_method(:default!)  { registry.mark_default(self) }
    end

    Module.new do
      define_method(:initialize) do |**kwargs|
        instance_variable_set(:"@#{inject}", kwargs.fetch(inject) do
          raise ArgumentError, "missing keyword: :#{inject}"
        end)
      end

      attr_reader inject
      protected inject

      define_singleton_method(:included) { |base| base.extend(class_methods) }
    end
  end
end
