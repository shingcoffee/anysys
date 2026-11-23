# frozen_string_literal: true

module AiAssistant
  module Subsystems
    # Processing an earlier build of the customer wrote, which a later build
    # may rewrite in place. Any other flowchart by that name, shared or built
    # by hand, stays out of a build's reach.
    module EarlierProcessing
      module_function

      def find(customer_id, name)
        flowchart = Flowchart.where(customer_id: customer_id, name: name.to_s.squish).where.not(status: :deleted).first
        flowchart if flowchart && written_ids(customer_id).include?(flowchart.id)
      end

      def written_ids(customer_id)
        AiAssistant::SubsystemBuild.unscoped.where(customer_id: customer_id).pluck(:results).flat_map do |results|
          processing = results.is_a?(Hash) ? results["processing"] : nil
          next [] unless processing.is_a?(Hash)

          processing.values.filter_map { |state| state["flowchart_id"] if state.is_a?(Hash) && state["status"] == "created" }
        end.to_set
      end
    end
  end
end
