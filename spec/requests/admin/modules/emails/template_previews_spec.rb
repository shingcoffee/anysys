require 'rails_helper'

RSpec.describe "Admin::Modules::Emails::TemplatePreviews", type: :request do
  include_context "as admin"

let!(:email_module) { enable_module!("email", customer, name: "Email") }

  describe "POST /:customer_id/admin/modules/emails/templates/:id/preview" do
    let(:template) do
      create(:email_template,
             customer: customer,
             subject: "Hello #{platform_token('first_name')}",
             body_html: "<h1>Welcome #{platform_token('first_name')}</h1>",
             body_text: "Welcome #{platform_token('first_name')}")
    end
    let(:guard_path) { preview_admin_modules_emails_template_path(customer.id, template) }

    it_behaves_like "an admin-guarded request", :post

    it "returns rendered subject, HTML, and text" do
      # Mock the variable context
      allow(Emails::VariableContext).to receive(:for).with(user: admin).and_return({ "first_name" => "Alice" })

      post preview_admin_modules_emails_template_path(customer.id, template)

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)

      expect(json["subject"]).to eq("Hello Alice")
      expect(json["body_html"]).to include("Welcome Alice")
      expect(json["body_text"]).to eq("Welcome Alice")
    end

    it "accepts custom vars via JSON params" do
      post preview_admin_modules_emails_template_path(customer.id, template), params: { vars: { "first_name" => "Bob" }.to_json }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)

      expect(json["subject"]).to eq("Hello Bob")
    end

    it "accepts custom vars via hash params" do
      post preview_admin_modules_emails_template_path(customer.id, template), params: { vars: { "first_name" => "Charlie" } }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["subject"]).to eq("Hello Charlie")
    end

    it "returns 422 when vars is a JSON array" do
      post preview_admin_modules_emails_template_path(customer.id, template),
           params: { vars: "[]" }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("Vars must be an object")
    end

    it "returns 422 when vars is a form array" do
      post preview_admin_modules_emails_template_path(customer.id, template),
           params: { vars: ["x"] }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("Vars must be an object")
    end

    it "returns 404 for unknown template" do
      post preview_admin_modules_emails_template_path(customer.id, id: 999999)
      expect(response).to have_http_status(:not_found)
    end

    it "does not inject tracking rewrites so preview matches authored content" do
      template.update!(body_html: '<p>See <a href="https://example.com">link</a></p>')

      post preview_admin_modules_emails_template_path(customer.id, template)

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["body_html"]).not_to include("/email/track/")
      expect(json["body_html"]).to include('href="https://example.com"')
    end

    context "with a rich_text template" do
      let(:template) do
        create(:email_template,
               customer: customer,
               editor_type: "rich_text",
               subject: "Hello #{platform_token('first_name')}",
               body: "<h1>Hello Dave</h1>")
      end

      it "compiles the template before rendering" do
        allow(Emails::VariableContext).to receive(:for).with(user: admin).and_return({ "first_name" => "Dave" })
        # sync_body_html! (controller) + TemplateRenderer both compile so the
        # preview stays aligned with send even when body_html is stale.
        expect(Emails::CompileTemplate).to receive(:call).with(template).at_least(:once).and_call_original

        post preview_admin_modules_emails_template_path(customer.id, template)

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["subject"]).to eq("Hello Dave")
      end

      it "returns editor fragment HTML without ActionText layout chrome" do
        post preview_admin_modules_emails_template_path(customer.id, template)

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["body_html"]).to include("Hello Dave")
        expect(json["body_html"]).not_to include("trix-content")
        expect(json["body_html"]).not_to include("BEGIN")
      end
    end
  end
end
