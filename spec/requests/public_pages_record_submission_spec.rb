# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Page submission saves the page's record", type: :request do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Title", "name_slug" => "title", "type" => "String", "html_type" => "text",
        "validators" => [{ "type" => "presence" }] }
    ].to_json)
  end

  def page_with(form_settings = {})
    Current.set(customer: customer) do
      create(:page, :public_only, customer: customer, entity: entity, launched: true, configuration: {
        pages: [{ id: "page_1", name: "Form", order: 1, fields: [
          { id: "f1", field_type: "text", property_slug: "title", property_type: "string", label: "Title",
            source: "entity", source_section: entity.display_label }
        ] }],
        metadata: { entity_id: entity.id },
        form_settings: form_settings
      }.to_json)
    end
  end

  def submit(page, title)
    post "/#{customer.id}/page/#{page.public_uuid}", params: { entity: { title: title } }
  end

  it "creates the record through the page's bound flowchart" do
    expect { submit(page_with, "Hello") }.to change { EntityEntry.where(entity_id: entity.id).count }.by(1)
    expect(flash[:notice]).to eq(I18n.t("public_views.flash.response_submitted"))
  end

  it "shows entity validation errors and writes nothing" do
    expect { submit(page_with, "") }.not_to(change { EntityEntry.where(entity_id: entity.id).count })
    expect(flash[:alert]).to be_present
  end

  it "uses the bound flowchart's outcome message as the flash" do
    page = page_with
    bind_page_flowchart(page, body: 'ctx[:submission_outcome] = { "preset" => "custom", "message" => "Welcome aboard" }; true')
    submit(page, "Hello")
    expect(flash[:notice]).to eq("Welcome aboard")
  end

  it "rolls back when the bound flowchart refuses the record" do
    page = page_with
    bind_page_flowchart(page, body: 'ctx[:errors] = ["Closed for enrolment"]; false')
    expect { submit(page, "Hello") }.not_to(change { EntityEntry.where(entity_id: entity.id).count })
    expect(flash[:alert]).to include("Closed for enrolment")
  end

  it "refuses an admin edit on a create-only page" do
    admin = create(:user, :admin, customer: customer)
    sign_in admin
    entry = EntityEntry.build_for(entity).create!(entity: entity, customer_id: customer.id, data: { "title" => "A" }.to_json)
    page = page_with("modes" => ["create"])
    page.update!(audience_admin: true)
    post "/#{customer.id}/page/#{page.public_uuid}?return_to=entity_entry&entry_id=#{entry.id}", params: { entity: { title: "B" } }
    expect(response).to have_http_status(:method_not_allowed)
  end
end
