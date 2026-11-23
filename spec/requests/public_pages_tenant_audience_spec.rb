# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public page tenant-bound runtime audiences", type: :request do
  let(:customer) { create(:customer) }
  let(:foreign_customer) { create(:customer) }
  let(:schema) do
    [
      { "name" => "Public name", "name_slug" => "public_name", "type" => "String", "html_type" => "text" },
      { "name" => "Admin-only note", "name_slug" => "admin_note", "type" => "String", "html_type" => "text",
        "visibility" => { "admin" => true, "member" => false, "public" => false } },
      { "name" => "Member-only note", "name_slug" => "member_note", "type" => "String", "html_type" => "text",
        "visibility" => { "admin" => true, "member" => true, "public" => false } }
    ]
  end
  let(:entity) { create(:entity, customer: customer, property_schema: schema.to_json) }
  let(:fields) do
    schema.map do |attribute|
      { "id" => attribute.fetch("name_slug"), "property_slug" => attribute.fetch("name_slug"),
        "source" => "entity", "html_type" => "text", "field_type" => "text", "label" => attribute.fetch("name") }
    end
  end
  let(:page) do
    Current.set(customer: customer) do
      create(:page, :for_member, :for_public, customer: customer, entity: entity, launched: true, configuration: {
        "metadata" => {}, "pages" => [{ "id" => "page_1", "fields" => fields }],
        "form_settings" => {}
      }.to_json)
    end
  end
  let(:canonical_path) { public_page_path(customer.id, page.public_uuid) }
  let(:submitted) { { public_name: "Public value", admin_note: "Forged admin value", member_note: "Forged member value" } }

  def input_names
    Nokogiri::HTML(response.body).css("input[name]").map { |input| input["name"] }
  end

  %i[admin member].each do |role|
    context "with a foreign-tenant #{role}" do
      let(:visitor) { create(:user, role, customer: foreign_customer) }
      before { sign_in visitor }

      it "renders only public fields while preserving the real authenticated actor" do
        get canonical_path

        expect(response).to have_http_status(:ok)
        expect(input_names).to include("entity[public_name]")
        expect(input_names).not_to include("entity[admin_note]", "entity[member_note]")
        expect(response.body).not_to include("Admin-only note", "Member-only note")

        # The same session is still recognized on its own protected surface.
        get "/#{foreign_customer.id}/#{role == :admin ? 'admin/maintenance/customer_profile' : 'member/profile'}"
        expect(response).to have_http_status(:ok)
      end

      it "discards privileged fields and spoofed audience/actor hints before persistence" do
        expect do
          post canonical_path, params: { entity: submitted, audience: "admin", current_user_role: "owner", current_user_id: visitor.id }
        end.to change { EntityEntry.where(customer_id: customer.id, entity_id: entity.id).count }.by(1)

        expect(response).to have_http_status(:redirect)
        entry = EntityEntry.where(customer_id: customer.id, entity_id: entity.id).order(:id).last
        expect(entry.data_json).to eq("public_name" => "Public value")
      end

      it "applies the same public audience on a clean alias GET and POST" do
        PageShortcut.create!(customer: customer, path: "/audience-form", target: page)
        path = "/#{customer.id}/audience-form"

        get path
        expect(response).to have_http_status(:ok)
        expect(request.path_parameters).to include(controller: "public_pages", action: "show")
        expect(input_names).not_to include("entity[admin_note]", "entity[member_note]")

        post path, params: { entity: submitted, audience: "admin" }
        expect(response).to have_http_status(:redirect)
        expect(request.path_parameters).to include(controller: "public_pages", action: "submit")
        expect(EntityEntry.where(customer_id: customer.id, entity_id: entity.id).order(:id).last.data_json)
          .to eq("public_name" => "Public value")
      end

      it "does not admit that actor to a narrower public endpoint or member route" do
        Current.set(customer: customer) { page.update!(audience_public: false) }
        get canonical_path
        expect(response).to have_http_status(:not_found)

        expect { post canonical_path, params: { entity: submitted } }.not_to change(EntityEntry, :count)
        expect(response).to have_http_status(:not_found)

        get "/#{customer.id}/member/pages/#{page.id}.json"
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  { member: %w[public_name member_note], admin: %w[public_name admin_note member_note] }.each do |role, allowed|
    it "retains the #{role} audience for a same-tenant authenticated actor" do
      sign_in create(:user, role, customer: customer)
      get canonical_path
      expect(response).to have_http_status(:ok)
      expect(input_names & %w[entity[public_name] entity[admin_note] entity[member_note]])
        .to match_array(allowed.map { |slug| "entity[#{slug}]" })

      post canonical_path, params: { entity: submitted }
      expect(response).to have_http_status(:redirect)
      expected = submitted.stringify_keys.slice(*allowed)
      expect(EntityEntry.where(customer_id: customer.id, entity_id: entity.id).order(:id).last.data_json).to eq(expected)
    end
  end

  it "retains the fixed platform owner's cross-tenant field privileges" do
    sign_in find_or_create_platform_owner
    get canonical_path
    expect(response).to have_http_status(:ok)
    expect(input_names).to include("entity[public_name]", "entity[admin_note]", "entity[member_note]")

    post canonical_path, params: { entity: submitted }
    expect(response).to have_http_status(:redirect)
    expect(EntityEntry.where(customer_id: customer.id, entity_id: entity.id).order(:id).last.data_json).to eq(submitted.stringify_keys)
  end

  %w[query entity_entries].each do |options_source|
    it "does not expose privileged #{options_source} labels to a foreign admin" do
      options_entity = create(:entity, customer: customer, property_schema: [{
        "name" => "Secret label", "name_slug" => "secret_label", "visibility" => { "public" => false }
      }].to_json)
      create(:entity_entry, customer: customer, entity: options_entity, data: { secret_label: "Hidden option sentinel" }.to_json)
      config = page.configuration_json
      config["pages"][0]["fields"] = [{
        "id" => "choice", "property_slug" => "choice", "field_type" => "select", "html_type" => "select",
        "dynamic_options" => { "options_source" => options_source, "entity_id" => options_entity.id,
                               "label_field" => "secret_label" }
      }]
      entity.update!(property_schema: [{ "name" => "Choice", "name_slug" => "choice", "html_type" => "select" }].to_json)
      Current.set(customer: customer) { page.update!(configuration: config.to_json) }
      sign_in create(:user, :admin, customer: foreign_customer)

      get canonical_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Hidden option sentinel")
      expect(Nokogiri::HTML(response.body).css("select option:not([value=''])")).to be_empty
    end
  end

  it "filters composite list headings and stored values for a foreign authenticated admin" do
    create(:entity_entry, customer: customer, entity: entity,
           data: { public_name: "Public row sentinel", admin_note: "Secret row sentinel" }.to_json)
    config = page.configuration_json.merge("layout" => "composite", "modules" => [{
      "id" => "records", "module_type" => "list", "entity_id" => entity.id,
      "config" => { "columns" => %w[public_name admin_note member_note] }
    }])
    Current.set(customer: customer) { page.update!(configuration: config.to_json) }
    sign_in create(:user, :admin, customer: foreign_customer)

    get canonical_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Public row sentinel")
    expect(response.body).not_to include("Secret row sentinel", "Admin-only note", "Member-only note")
  end

  it "does not export a privileged value a foreign visitor posted through a flowchart module handoff" do
    registration = Class.new(FeatureModules::BaseModule) do
      def self.module_key = "audience_demo"
      def self.module_name = "Audience demo"
      def self.provision!(_customer) = nil
      entry_path { |tenant| "/#{tenant.id}/audience-demo" }
      input_contract { property :exported_note }
    end
    feature_module = create(:feature_module, :handoffable, key: "audience_demo")
    create(:customer_feature_module, customer: customer, feature_module: feature_module)
    allow_any_instance_of(FeatureModules::Module).to receive(:registration_class).and_wrap_original do |original|
      original.receiver.key == feature_module.key ? registration : original.call
    end
    bind_page_flowchart(page, body: <<~RUBY)
      ctx[:model].data_json = ctx[:params]
      ctx[:model].save!
      FlowchartRuntime::Handoff.request(ctx, module_key: #{feature_module.key.inspect},
                                        input: { "exported_note" => ctx[:params]["admin_note"] })
    RUBY
    sign_in create(:user, :admin, customer: foreign_customer)

    post canonical_path, params: { entity: submitted }

    expect(response).to redirect_to("/#{customer.id}/handoff")
    expect(session[:feature_module_invocation][:input][:exported_note]).to be_nil
    saved = EntityEntry.where(customer_id: customer.id, entity_id: entity.id).sole
    expect(saved.data_json).to eq("public_name" => "Public value")
  end
end
