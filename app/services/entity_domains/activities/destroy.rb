# frozen_string_literal: true

module EntityDomains
  module Activities
    # Permanently deletes a domain with everything it holds (see Contents):
    # its journeys, the pages bound to its entities, and the entities with
    # their records. Refused while entities of other domains still link in.
    # Runs under the customer lock the assistant's operations write under, so
    # nothing joins the domain between the check and the delete; a failure
    # deletes nothing.
    class Destroy
      def self.call(domain:, customer_id:)
        domain.errors.clear

        if !domain.persisted? || domain.customer_id.to_s != customer_id.to_s
          domain.errors.add(:base, I18n.t("maint_core.entity_domains.errors.invalid_customer"))
        else
          domain.customer.with_lock { delete_unless_linked!(domain, Contents.new(domain)) }
        end

        Save::Result.new(success?: domain.errors.empty?, model: domain, errors: domain.errors.messages.to_h)
      rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey => e
        domain.errors.add(:base, I18n.t("maint_core.entity_domains.errors.delete_failed", error: e.message))
        Save::Result.new(success?: false, model: domain, errors: domain.errors.messages.to_h)
      end

      def self.delete_unless_linked!(domain, contents)
        if (links = contents.outside_links).any?
          return domain.errors.add(:base, I18n.t("maint_core.entity_domains.errors.linked_from_outside",
                                                 names: links.map(&:display_label).to_sentence))
        end

        contents.journeys.destroy_all
        contents.pages.each(&:destroy!)
        contents.entities.sort_by { |entity| entity.bridge_entity? ? 0 : 1 }.each(&:destroy!)
        domain.destroy!
      end
      private_class_method :delete_unless_linked!
    end
  end
end
