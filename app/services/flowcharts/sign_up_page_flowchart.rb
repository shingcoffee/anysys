# frozen_string_literal: true

module Flowcharts
  # The platform's shared "Member sign-up" flowchart for public pages on a
  # person entity: it validates the page, registers the visitor as a
  # passwordless member (register_member, which saves the person record with
  # its identity and parks the claim), then saves the page's own fields.
  # Generated public sign-up pages bind it (Journeys::Activities::Generate).
  module SignUpPageFlowchart
    UUID = "3b8e6f1d-92c4-4a7e-b5d0-6f1c2a9e8d47"

    module_function

    # Created on first use, like DefaultPageFlowchart. Once the platform owner
    # deletes it, it stays deleted and nothing binds it any more.
    def fetch
      existing = Flowchart.unscoped.find_by(customer_id: nil, uuid: UUID)
      return create! unless existing

      existing unless existing.deleted?
    end

    # Like DefaultPageFlowchart.for_customer: the customer's own copy once
    # this one is deleted.
    def for_customer(customer) = fetch || CustomerCopy.fetch(customer, self)

    def create!
      Current.set(shared_resources_mode: true) do
        Flowchart.new_with_defaults(**attributes, uuid: UUID, status: :launched, customer_id: nil).tap(&:save!)
      end
    rescue ActiveRecord::RecordNotUnique
      Flowchart.unscoped.find_by!(customer_id: nil, uuid: UUID)
    end

    def attributes
      {
        name: I18n.t("maint_core.flowcharts.sign_up_page_flowchart.name", locale: I18n.default_locale),
        description: I18n.t("maint_core.flowcharts.sign_up_page_flowchart.description", locale: I18n.default_locale),
        template: "member_signup"
      }
    end
  end
end
