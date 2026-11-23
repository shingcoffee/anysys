# frozen_string_literal: true

module Member
  module Sources
    class Entities < Member::SurfaceSource
      def self.key         ; :entities ; end
      def self.name        ; I18n.t("maint_core.nav.entities") ; end
      def self.description ; I18n.t("admin_settings.member.sources.entities.description") ; end
      def self.position    ; 20 ; end

      def surfaces
        catalog.filter_map { |entity|
          next unless surfaceable?(entity)

          Member::EntitySurfaceBuilder.call(entity: entity, customer: customer)
        }
      end

      def catalog
        ::Entity.where(customer_id: [customer.id, nil])
      end

      def surfaceable?(entity)
        kind = People::Ownership.kind(entity)
        return false if kind == :private
        return false if entity.bridge_entity? && kind != :owned

        true
      end
      private :catalog, :surfaceable?

      register!
    end
  end
end
