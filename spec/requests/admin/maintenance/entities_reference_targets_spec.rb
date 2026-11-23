# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Entities reference targets", type: :request do
  include_context "as admin"

  let!(:course) do
    create(:entity, customer: customer, name: "Course", property_schema: [
      { "name" => "Title", "name_slug" => "title", "html_type" => "text" },
      { "name" => "Notes", "name_slug" => "notes", "html_type" => "textarea" }
    ].to_json)
  end

  it "marks which attributes can label a reference" do
    get admin_maintenance_entities_path(customer.id, format: :json)

    item = response.parsed_body.find { |entity| entity["id"] == course.id }
    expect(item["property_schema"].to_h { |attr| [attr["name_slug"], attr["labelable"]] })
      .to eq("title" => true, "notes" => false)
  end

  it "rejects a member" do
    sign_in create(:user, :member, customer: customer)
    get admin_maintenance_entities_path(customer.id, format: :json)
    expect(response).to have_http_status(:forbidden)
      .or have_http_status(:found)
      .or have_http_status(:not_found)
  end
end
