# frozen_string_literal: true

module Member
  module Sources
    class Modules < Member::SurfaceSource
      def self.key         ; :modules ; end
      def self.name        ; I18n.t("maint_core.nav.modules") ; end
      def self.description ; I18n.t("admin_settings.member.sources.modules.description") ; end
      def self.position    ; 10 ; end

      def surfaces
        FeatureModules::Module.available_for_customer(customer.id).flat_map do |fm|
          ns_name = "FeatureModules::#{fm.key.camelize}"
          ns      = ns_name.safe_constantize or next []

          surface = resolve_member_surface(ns)
          next [] unless surface.is_a?(Member::Surface)

          surface.validate!
          [surface]
        end
      end

      register!

      private

      def resolve_member_surface(ns)
        return unless ns.const_defined?(:MemberSurface, false)

        raw = ns.const_get(:MemberSurface)
        return raw.build if raw.respond_to?(:build)

        raw
      end
    end
  end
end
