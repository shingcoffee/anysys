# frozen_string_literal: true

require "rails_helper"

# A page never saves on its own: its bound flowchart validates, saves and
# decides. When that flowchart refuses, the form comes back once with what
# was typed and each field's error beside it.
RSpec.describe "Public page submission errors", type: :request do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, name: "Signup", property_schema: [
      { "name" => "Name", "name_slug" => "name", "type" => "String", "html_type" => "text",
        "validators" => [{ "type" => "presence" }] },
      { "name" => "Nickname", "name_slug" => "nickname", "type" => "String", "html_type" => "text" },
      { "name" => "Pin", "name_slug" => "pin", "type" => "String", "html_type" => "password" }
    ].to_json)
  end
  let(:fields) do
    [{ "id" => "f_name", "property_slug" => "name", "source" => "entity", "label" => "Name", "html_type" => "text" },
     { "id" => "f_nickname", "property_slug" => "nickname", "source" => "entity", "label" => "Nickname", "html_type" => "text" },
     { "id" => "f_pin", "property_slug" => "pin", "source" => "entity", "label" => "Pin", "html_type" => "password" }]
  end
  let(:page) do
    Current.set(customer: customer) do
      create(:page, :for_public, customer: customer, entity: entity, launched: true,
                    configuration: { form_settings: { modes: ["create"] },
                                     metadata: { entity_id: entity.id, entity_name: entity.name },
                                     pages: [{ "id" => "p1", "fields" => fields }] }.to_json)
    end
  end
  let(:url) { "/#{customer.id}/page/#{page.public_uuid}" }

  def doc = Nokogiri::HTML(response.body)
  def field_errors(field_id) = doc.css("[data-field-id='#{field_id}'] [data-field-error] li").map { |item| item.text.strip }
  def fail_with(message, field: nil)
    bind_page_flowchart(page, body: <<~RUBY)
      return FlowchartRuntime::Step.fail_message(ctx, { "en" => #{message.inspect} }#{field ? ", field: #{field.inspect}" : ""})
    RUBY
  end

  it "shows a Fail with error step's message beside the field it names, keeping what was typed but never a password" do
    fail_with("Pick another nickname", field: "nickname")

    expect { post url, params: { entity: { name: "Ada", nickname: "ada", pin: "1234" } } }.not_to change(EntityEntry, :count)

    expect(URI(response.location).path).to eq(url)
    expect(flash[:alert]).to eq(I18n.t("public_views.flash.response_field_errors"))
    follow_redirect!

    expect(field_errors("f_nickname")).to eq(["Pick another nickname"])
    expect(field_errors("f_name")).to be_empty
    expect(doc.at_css("input[name='entity[nickname]']")["value"]).to eq("ada")
    expect(doc.at_css("input[name='entity[name]']")["value"]).to eq("Ada")
    expect(JourneyRun.last.state).not_to include("1234")

    get request.fullpath
    expect(doc.css("[data-field-error]")).to be_empty
    expect(doc.at_css("input[name='entity[nickname]']")["value"]).to be_blank
  end

  it "shows the contract's validation errors beside their fields" do
    post url, params: { entity: { name: "", nickname: "ada" } }
    follow_redirect!

    expect(field_errors("f_name")).to eq(["can't be blank"])
    expect(response.body).to include(CGI.escapeHTML(I18n.t("public_views.flash.response_field_errors")))
  end

  it "keeps an error with no field in the alert" do
    fail_with("We're closed today")

    post url, params: { entity: { name: "Ada" } }

    expect(flash[:alert]).to eq(I18n.t("public_views.flash.response_save_error", errors: "We're closed today"))
    follow_redirect!
    expect(doc.css("[data-field-error]")).to be_empty
  end

  it "keeps an error on a field the page doesn't show in the alert" do
    fail_with("Too late", field: "deadline")

    post url, params: { entity: { name: "Ada" } }

    expect(flash[:alert]).to eq(I18n.t("public_views.flash.response_save_error", errors: "Too late"))
  end

  it "saves through the flowchart and shows no errors when it succeeds" do
    expect { post url, params: { entity: { name: "Ada" } } }.to change(EntityEntry, :count).by(1)
    expect(flash[:notice]).to be_present
    expect(JourneyRun.count).to eq(0)
  end

  it "refuses the submission when the page has no launched flowchart" do
    page.update_column(:flowchart_id, nil)

    expect { post url, params: { entity: { name: "Ada" } } }.not_to change(EntityEntry, :count)

    expect(flash[:alert]).to eq(I18n.t("maint_core.errors.page_launch.submission_process_offline"))
    expect(flash[:alert]).not_to match(/flowchart/i)
  end

  it "never shows one visitor's refused submission to another browser" do
    fail_with("Nope", field: "nickname")
    post url, params: { entity: { name: "Ada", nickname: "ada" } }
    location = response.location

    reset!
    get location

    expect(doc.css("[data-field-error]")).to be_empty
    expect(doc.at_css("input[name='entity[nickname]']")["value"]).to be_blank
  end
end
