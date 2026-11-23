# frozen_string_literal: true

module Pages
  # A launched member page that manages the rows hanging off a member's
  # record (form_settings.manage_rows): the items of a cart, say. Its one
  # locked input names the record, and its entity's rows must belong to the
  # member through it (People::Ownership: owned or nested), so a member only
  # ever adds to, changes or removes from their own records. Every lookup
  # re-checks the page, the record and the row.
  module MemberRows
    MEMBER = EntityAttributeAudience::MEMBER
    ID = /\A[1-9]\d*\z/
    MEMBER_KINDS = %i[owned nested].freeze

    module_function

    def managing?(page)
      page.launched? && page.visible_to?(MEMBER) && page.manages_rows? && page.page_inputs.one? &&
        page.entity.present? && MEMBER_KINDS.include?(People::Ownership.kind(page.entity))
    end

    # The launched page managing +entity+'s rows from records of
    # +parent_entity_id+, a tenant page before a shared one.
    def page_for(entity:, parent_entity_id:, customer_id:)
      Page.where(customer_id: [customer_id, nil]).launched.for_audience(MEMBER).for_entity(entity.id)
          .sort_by { |page| [page.customer_id ? 0 : 1, page.id] }
          .find { |page| managing?(page) && page.page_inputs.first["entity_id"] == parent_entity_id.to_s }
    end

    # The record +record_id+ names, when it is of the locked input's type
    # and the member reaches it.
    def record(page:, record_id:, viewer:, customer_id:)
      return unless managing?(page) && record_id.to_s.match?(ID)

      entity = Entity.where(customer_id: [customer_id, nil]).find_by(id: page.page_inputs.first["entity_id"])
      return unless entity && reachable?(entity, record_id, viewer, customer_id)

      EntityEntry.find_by(customer_id: customer_id, entity_id: entity.id, id: record_id)
    end

    # The row +entry_id+ names, when it is of the page's entity, the member
    # reaches it and it hangs off a record the member reaches.
    def row(page:, entry_id:, viewer:, customer_id:)
      return unless managing?(page) && entry_id.to_s.match?(ID) && reachable?(page.entity, entry_id, viewer, customer_id)

      row = EntityEntry.build_for(page.entity).find_by(customer_id: customer_id, entity_id: page.entity.id, id: entry_id)
      row if row && record_of(page: page, row: row, viewer: viewer, customer_id: customer_id)
    end

    def record_of(page:, row:, viewer:, customer_id:)
      id = Array(row.data_json[page.page_inputs.first["field"]]).first
      record(page: page, record_id: id.to_s, viewer: viewer, customer_id: customer_id)
    end

    def reachable?(entity, id, viewer, customer_id)
      People::Ownership.reachable_ids(entity, [id], viewer: viewer, audience: MEMBER, customer_id: customer_id).include?(id.to_s)
    end
    private_class_method :reachable?
  end
end
