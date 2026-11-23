# frozen_string_literal: true

require "rails_helper"

# PageSubmissionNavigation: success goes to a module handoff, else the
# journey's next step, else the admin entry return, else the page's own
# success_message on the same page.
RSpec.describe "Page submission navigation", type: :request do
  include_context "as admin"
  include_context "student course association"

  def submit_path(page, **query)
    "/#{customer.id}/page/#{page.public_uuid}#{"?#{query.to_query}" if query.any?}"
  end

  it "flashes the page's success_message and stays on the public form" do
    sign_out admin
    page = student_journey_page(audience_admin: false, audience_public: true)
    config = page.configuration_json
    config["form_settings"] = config.fetch("form_settings", {}).merge("success_message" => "Welcome, student!")
    Current.set(customer: customer) { page.update!(configuration: config.to_json) }

    post submit_path(page), params: { entity: { full_name: "Grace" } }

    expect(flash[:notice]).to eq("Welcome, student!")
    expect(response).to redirect_to(submit_path(page))
  end

  it "sends an admin who submitted from the entries area back to the created entry" do
    page = Current.set(customer: customer) do
      create(:page, customer: customer, entity: student_entity, launched: true,
                    configuration: {
                      form_settings: { modes: ["create"] },
                      metadata: { entity_id: student_entity.id, entity_name: student_entity.name },
                      pages: [{ "id" => "page_1", "fields" => [
                        { "id" => "f_full_name", "property_slug" => "full_name", "source" => "entity",
                          "label" => "Full name", "html_type" => "text" }
                      ] }]
                    }.to_json)
    end

    post submit_path(page, return_to: PageRendering::ENTITY_ENTRY_RETURN), params: { entity: { full_name: "Grace" } }

    grace = EntityEntry.where(entity_id: student_entity.id, customer_id: customer.id).order(:id).last
    expect(grace.data_json["full_name"]).to eq("Grace")
    expect(response).to redirect_to(admin_entity_entry_path(customer.id, student_entity, grace.id))
    expect(flash[:notice]).to eq(I18n.t("admin_misc.entities.entry_form.created"))
  end

  it "follows the journey's next step after a successful submit" do
    student_page = student_journey_page
    course_page = course_journey_page
    create(:journey, :launched, customer: customer)

    post submit_path(student_page, return_to: PageRendering::ENTITY_ENTRY_RETURN), params: { entity: { full_name: "Grace" } }

    location = Addressable::URI.parse(response.location)
    expect(location.path).to eq(new_admin_entity_entry_path(customer.id, bridge_entity))
    expect(location.query_values).to include("page" => course_page.id.to_s, "run" => be_present)
  end
end
