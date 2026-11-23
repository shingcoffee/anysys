# frozen_string_literal: true

module Flowcharts
  # A customer's own launched copy of a platform singleton flowchart
  # (DefaultPageFlowchart, SignUpPageFlowchart), so the pages the assistant
  # generates still have processing once the platform owner has deleted the
  # shared one. Its uuid is derived from the singleton's and the customer's,
  # which keeps it to one copy per customer.
  module CustomerCopy
    module_function

    # A trashed copy comes back; one the platform owner took offline stays
    # offline. nil when the customer already has another flowchart by the
    # singleton's name.
    def fetch(customer, singleton)
      uuid = Digest::UUID.uuid_v5(singleton::UUID, customer.id.to_s)
      copy = Flowchart.unscoped.find_by(customer_id: customer.id, uuid: uuid)
      return create!(customer, singleton, uuid) unless copy

      copy.update!(status: :launched) if copy.deleted?
      copy
    end

    def create!(customer, singleton, uuid)
      Current.set(customer: customer, shared_resources_mode: false) do
        Flowchart.new_with_defaults(**singleton.attributes, uuid: uuid, status: :launched, customer_id: customer.id).tap(&:save!)
      end
    rescue ActiveRecord::RecordNotUnique
      Flowchart.unscoped.find_by!(customer_id: customer.id, uuid: uuid)
    rescue ActiveRecord::RecordInvalid
      nil
    end
  end
end
