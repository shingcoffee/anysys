# frozen_string_literal: true

module Pages
  # The only lookup from an entity to the launched page an audience creates
  # or edits its entries with: bound to the entity and serving the action
  # (Page#serves?). The visited tenant's page wins over a shared page, then
  # the newest.
  class EntryPageResolver
    ACTIONS = %i[create update].freeze

    class << self
      def page_for(entity:, audience:, action:)
        raise ArgumentError, "unknown action #{action.inspect}" unless ACTIONS.include?(action)

        Page.accessible.launched.for_audience(audience).for_entity(entity.id).to_a
            .sort_by { |page| [page.shared? ? 1 : 0, -page.id] }
            .find { |page| page.serves?(action) }
      end
    end
  end
end
