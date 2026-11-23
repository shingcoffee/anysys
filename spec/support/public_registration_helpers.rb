# frozen_string_literal: true

# Shared setup for a public Student page whose flowchart saves the record and
# then runs register_member (used by the registration request spec and
# pending-claim sign-in specs).
module PublicRegistrationHelpers
  def enable_authentication_signup!(customer)
    person_model = EntityDefinitions::Capabilities::PERSON_MODEL
    fm = enable_module!("authentication", customer)
    fm.set_extendable_model!(person_model, true)
    assignment = FeatureModules::CustomerAssignment.find_by!(
      customer_id: customer.id, feature_module_id: fm.id
    )
    assignment.update!(configuration: { "allow_registration" => true }.to_json)
    fm
  end

  def stub_member_quota_allow!
    allow_guard = instance_double(Billing::Quota::Guard::Result, allowed?: true, message: "allowed")
    allow(Billing::Quota::Guard).to receive(:check).and_return(allow_guard)
  end

  def build_student_entity(customer)
    person_model = EntityDefinitions::Capabilities::PERSON_MODEL
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)
    create(:entity, customer: customer, name: "Student", extended_model: person_model)
  end

  REGISTER_MEMBER_STEP = { "action" => "register_member", "config" => { "personVar" => "model", "resultVar" => "registration" } }.freeze

  def build_public_registration_page(customer:, entity:, action_key: nil, traits: %i[for_member for_public])
    page = Current.set(customer: customer) do
      attrs = {
        customer: customer,
        entity: entity,
        launched: true,
        configuration: {
          metadata: { entity_id: entity.id, entity_name: entity.name },
          pages: [{ "id" => "p1", "fields" => identity_fields }]
        }.to_json
      }
      attrs[:action_key] = action_key if action_key
      create(:page, *traits, **attrs)
    end
    bind_page_flowchart(page, steps: [REGISTER_MEMBER_STEP])
    page
  end

  def identity_fields
    People::IDENTITY_KEYS.map do |key|
      html_type = key == "email" ? "email" : "text"
      { "id" => "id_#{key}", "property_slug" => key, "source" => "identity",
        "html_type" => html_type, "field_type" => html_type, "label" => key.humanize }
    end
  end
end

RSpec.configure do |config|
  config.include PublicRegistrationHelpers, type: :request
end
