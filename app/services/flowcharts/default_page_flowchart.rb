# frozen_string_literal: true

module Flowcharts
  # The platform's shared "Save page record" flowchart: it validates the
  # page's input against the page's entity and saves the record the page
  # submits. Every new page binds it until the platform owner binds one that
  # does more.
  module DefaultPageFlowchart
    UUID = "7d4f3a52-6c1e-4b8a-9f0e-2a5d8c1b3e70"

    module_function

    # Created on first use, like other platform singletons. Once the platform
    # owner deletes it, it stays deleted: new pages start unbound.
    def fetch
      existing = Flowchart.unscoped.find_by(customer_id: nil, uuid: UUID)
      return create! unless existing

      existing unless existing.deleted?
    end

    # What the assistant binds a page it generates for +customer+ to: this
    # flowchart, or once the platform owner has deleted it, the customer's own
    # copy (CustomerCopy), so the assistant never depends on it existing.
    def for_customer(customer) = fetch || CustomerCopy.fetch(customer, self)

    # Shared-resources mode keeps the first version on the global line; under a
    # tenant's Current.customer it would become that tenant's override instead.
    def create!
      Current.set(shared_resources_mode: true) do
        Flowchart.new_with_defaults(**attributes, uuid: UUID, status: :launched, customer_id: nil).tap(&:save!)
      end
    rescue ActiveRecord::RecordNotUnique
      Flowchart.unscoped.find_by!(customer_id: nil, uuid: UUID)
    end

    def attributes
      {
        name: I18n.t("maint_core.flowcharts.default_page_flowchart.name", locale: I18n.default_locale),
        description: I18n.t("maint_core.flowcharts.default_page_flowchart.description", locale: I18n.default_locale),
        template: "page_record"
      }
    end

    def default?(flowchart) = flowchart&.uuid == UUID && flowchart.shared?
  end
end
