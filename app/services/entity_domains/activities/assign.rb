# frozen_string_literal: true

module EntityDomains
  module Activities
    # Moves one entity, with the bridges it declares, into another domain of
    # the customer. An entity always belongs to a domain, so a domain is
    # required.
    class Assign
      def self.call(entity:, domain_id:, customer_id:)
        entity.errors.clear
        cid = customer_id.to_s.match?(Save::ID) ? customer_id.to_i : nil
        domain = EntityDomain.for_customer(cid).find_by(id: domain_id) if cid && domain_id.to_s.match?(Save::ID)

        if cid.nil? || !Catalog.entities(cid).exists?(id: entity.id)
          entity.errors.add(:base, I18n.t("maint_core.entity_domains.errors.invalid_customer"))
        elsif domain.nil?
          entity.errors.add(:base, I18n.t("maint_core.entity_domains.errors.domain_unavailable"))
        else
          EntityDomainMembership.transaction { Memberships.place!(entity, domain) }
        end

        Save::Result.new(success?: entity.errors.empty?, model: entity, errors: entity.errors.messages.to_h)
      end
    end
  end
end
