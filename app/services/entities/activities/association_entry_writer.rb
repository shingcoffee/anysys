# frozen_string_literal: true

module Entities
  module Activities
    # Steps shared by the bridge row writers (CreateAssociationEntries /
    # UpdateAssociationEntry): the primary entry must be a record of an active
    # non-bridge entity in this customer, and the association one it declares.
    module AssociationEntryWriter
      include EntryWriter

      def authorize(ctx, customer:, actor:, entity:, entry:, association_id:, **)
        return false unless super(ctx, customer: customer, actor: actor, entity: entity)

        ctx[:entry] = EntityEntry.find_by(id: entry&.id, customer_id: customer.id, entity_id: ctx[:entity].id)
        return false unless ctx[:entry]

        ctx[:association] = EntryAssociations.new(entity: ctx[:entity], customer: customer).find(association_id)
        ctx[:association].present?
      end

      private

      def association_form(ctx, params:, row: nil)
        EntryForm.new(entity: ctx[:association].bridge, customer: ctx[:customer], params: params, entry: row,
                      links: ctx[:association].links(ctx[:entry]))
      end
    end
  end
end
