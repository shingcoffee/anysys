# frozen_string_literal: true

module Flowcharts
  # The entity the editor offers attribute pickers for: the one entity every
  # page bound to the flowchart submits, or nil when it serves several (or
  # none yet). Only the pages the editing customer can see count.
  module DesignEntity
    module_function

    # +customer_id+ nil means Shared Resources: only shared pages count.
    def for(flowchart, customer_id:)
      return unless flowchart&.persisted?

      owners = [customer_id, nil].uniq
      entity_ids = flowchart.pages.where(customer_id: owners).filter_map(&:entity_id).map(&:to_s).uniq
      return unless entity_ids.one?

      Entity.where(customer_id: owners).find_by(id: entity_ids.first)
    end
  end
end
