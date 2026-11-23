# frozen_string_literal: true

# PageProcessing
#
# Binds a page to the flowchart that processes its submissions. Every submit
# runs that flowchart, unconditionally; it owns validation, writes, side
# effects and the outcome. A customer's page may bind one of the customer's
# flowcharts or a shared one; a shared page only a shared one (a tenant
# customises a shared flowchart through its own override, never a rebind).
#
# A new page binds the platform's default "Save page record" flowchart.
module PageProcessing
  extend ActiveSupport::Concern

  included do
    belongs_to :flowchart, optional: true

    before_validation :bind_default_flowchart, on: :create
    validate :flowchart_belongs_to_page_owner
  end

  # Flowcharts this page may bind: the owner's own and the shared ones.
  def bindable_flowcharts
    Flowchart.where(customer_id: [customer_id, nil].uniq)
  end

  # Whether a submit ends in a module (checkout, …) rather than on the page,
  # read from the definition +for_customer+ runs (its override of a shared
  # flowchart, if any).
  def hands_off?(for_customer: customer)
    return false unless flowchart

    Current.with_customer(for_customer) { FlowchartRuntime::RuntimeFlowchart.new(flowchart).hands_off? }
  end

  private

  def bind_default_flowchart
    self.flowchart ||= Flowcharts::DefaultPageFlowchart.fetch
  end

  def flowchart_belongs_to_page_owner
    return if flowchart_id.blank? || bindable_flowcharts.exists?(id: flowchart_id)

    errors.add(:flowchart_id, I18n.t("maint_core.errors.validations.page_flowchart_unavailable"))
  end
end
