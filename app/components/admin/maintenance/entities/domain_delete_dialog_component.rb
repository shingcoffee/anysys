# frozen_string_literal: true

module Admin
  module Maintenance
    module Entities
      # "Delete domain" button and its confirmation dialog. The dialog lists
      # what EntityDomains::Activities::Destroy removes, and replaces the
      # delete button with the reason when entities of other domains still
      # link into this one.
      class DomainDeleteDialogComponent < ApplicationComponent
        attr_reader :domain

        def initialize(domain:, customer_id:)
          @domain = domain
          @customer_id = customer_id
        end

        def dialog_id = "entity-domain-#{domain.id}-delete"
        def destroy_path = helpers.admin_maintenance_entity_domain_path(@customer_id, domain)

        def contents = @contents ||= ::EntityDomains::Contents.new(domain)
        def outside_links = contents.outside_links
        def blocked? = outside_links.any?
        def blocked_message
          t("maint_core.entity_domains.errors.linked_from_outside", names: outside_links.map(&:display_label).to_sentence)
        end

        def shared_count = domain.memberships.count - contents.entities.size

        def impact_lines
          [
            t("maint_core.entity_domains.delete_dialog.entities", count: contents.entities.size),
            t("maint_core.entity_domains.delete_dialog.records", count: contents.record_count),
            t("maint_core.entity_domains.delete_dialog.pages", count: contents.pages.size),
            t("maint_core.entity_domains.delete_dialog.journeys", count: contents.journeys.count)
          ]
        end
      end
    end
  end
end
