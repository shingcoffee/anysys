# frozen_string_literal: true

module Entities
  # The launched admin page that saves one association's link rows for a
  # record, so the record page's Add (create) and Edit (update) go through the
  # page and its flowchart instead of writing the rows directly. The page must
  # be bound to the link entity, serve the action, and lock exactly the
  # reference back to the record, which the dialog pins (JourneyRun.pin!).
  module AssociationPages
    module_function

    # +association+: an Entities::EntryAssociations::Association of +entity+.
    def find(association:, entity:, customer_id:, mode:)
      input = { "field" => association.source_slug.to_s, "entity_id" => entity.id.to_s }
      Page.where(customer_id: [customer_id, nil]).launched.for_audience(EntityAttributeAudience::ADMIN)
          .for_entity(association.bridge.id).order(:id)
          .find { |page| page.serves?(mode) && page.page_inputs == [input] }
    end
  end
end
