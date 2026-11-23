# frozen_string_literal: true

require "rails_helper"

# Coverage for tenant-scoping and template-injection guards in
# PageContentGenerator. Each example pins down a security property that
# is otherwise easy to regress when adding fields or templates.
RSpec.describe PageContentGenerator, "safety hardening" do
  let(:tenant_a) { create(:customer) }
  let(:tenant_b) { create(:customer) }
  around { |example| Current.set(customer: tenant_a, user: nil, shared_resources_mode: false) { example.run } }

  describe "dynamic-option entity lookup is scoped to the page's customer" do
    let(:entity_a) { create(:entity, customer: tenant_a, name: "alpha") }
    let(:entity_b) { create(:entity, customer: tenant_b, name: "beta") }

    it "ignores an entity_id that belongs to a different tenant" do
      page = create(:page, customer: tenant_a, configuration_json: {
        "fields" => [
          {
            "type" => "select",
            "slug" => "owner",
            "label" => "Owner",
            "dynamic_options" => {
              "options_source" => "query",
              "entity_id" => entity_b.id, # foreign tenant
              "label_field" => "name"
            }
          }
        ]
      })

      gen = described_class.new(page)
      fields = gen.send(:resolve_dynamic_options, page.configuration_json["fields"])

      # The dynamic_options must be left intact (no `dynamic_options.options`
      # populated) — i.e. the foreign-tenant entity is not loaded.
      resolved = fields.first
      expect(resolved.dig("dynamic_options", "options")).to be_nil
    end

    it "resolves an entity_id that belongs to the same tenant" do
      page = create(:page, customer: tenant_a, configuration_json: {
        "fields" => [
          {
            "type" => "select",
            "slug" => "owner",
            "label" => "Owner",
            "dynamic_options" => {
              "options_source" => "query",
              "entity_id" => entity_a.id,
              "label_field" => "name"
            }
          }
        ]
      })

      gen = described_class.new(page)
      # Just confirm no exception — the lookup succeeds for the same tenant.
      expect { gen.send(:resolve_dynamic_options, page.configuration_json["fields"]) }.not_to raise_error
    end
  end

  describe "submit_button_text is rendered as a Ruby string literal" do
    it "quotes a value containing a double-quote and #{} so it cannot inject code" do
      page = create(:page, customer: tenant_a, configuration_json: {
        "settings" => { "submit_button_text" => 'Done"; system("id"); "' },
        "pages"    => [
          {
            "id" => "p1",
            "fields" => [
              { "type" => "text", "slug" => "name", "label" => "Name" }
            ]
          }
        ]
      })
      content = described_class.new(page).generate
      # The dangerous payload must be embedded as an escaped string literal,
      # not as raw Ruby. Confirm the unescaped form never appears.
      expect(content).not_to include('Done"; system("id");')
      # And confirm the escaped form (\" instead of ") does appear.
      expect(content).to include('\\"; system(\\"id\\"); \\"')
    end
  end

  describe "field and layout-element text are rendered as Ruby string literals" do
    # html_escape does NOT neutralise `#{...}` or a trailing backslash, so a value
    # interpolated into a double-quoted Ruby literal that is later `render inline:`d
    # would otherwise allow arbitrary Ruby execution on the public page.
    let(:payload) { 'x#{system("id")}y"; system("id"); "' }

    it "escapes a malicious data-field label so it cannot inject code" do
      entity = create(:entity, customer: tenant_a, property_schema: [{ "name_slug" => "name", "type" => "String" }].to_json)
      page = create(:page, customer: tenant_a, entity: entity, configuration_json: {
        "pages" => [{
          "id" => "p1",
          "fields" => [
            { "id" => "f1", "field_type" => "text", "html_type" => "text",
              "property_slug" => "name", "label" => payload, "placeholder" => payload }
          ]
        }]
      })
      content = described_class.new(page).generate

      # The live interpolation marker must never appear unescaped in the source.
      expect(content).not_to include('#{system("id")}')
      # It is present only in escaped form (\#{...}, \" instead of ").
      expect(content).to include('\#{system(\"id\")}')
    end

    it "escapes malicious layout-element (heading) content" do
      page = create(:page, customer: tenant_a, configuration_json: {
        "pages" => [{
          "id" => "p1",
          "fields" => [
            { "id" => "f1", "field_type" => "heading", "property_type" => "layout",
              "content" => payload }
          ]
        }]
      })
      content = described_class.new(page).generate

      expect(content).not_to include('#{system("id")}')
      expect(content).to include('\#{system(\"id\")}')
    end
  end

  describe "entity_entries dropdown labels are not ActiveRecord send" do
    it "lists entity records through Entities::ReferenceOptions instead of sending AR methods" do
      entity = create(:entity, customer: tenant_a, property_schema: [{ "name_slug" => "owner", "type" => "String" }].to_json)
      page = create(:page, customer: tenant_a, entity: entity, configuration_json: {
        "pages" => [{
          "id" => "p1",
          "fields" => [
            {
              "id" => "owner",
              "property_slug" => "owner",
              "html_type" => "select",
              "label" => "Owner",
              "dynamic_options" => {
                "options_source" => "entity_entries",
                "entity_id" => 1,
                "label_field" => "destroy"
              }
            }
          ]
        }]
      })
      content = described_class.new(page).generate
      expect(content).to include('Entities::ReferenceOptions.call(entity_id: 1, label_field: "destroy"')
      expect(content).to include("EntityAttributeAudience.for_user(Current.user, customer_id: __cid)")
      expect(content).to include("viewer: Current.user")
      expect(content).not_to include("EntityEntry.build_for")
      expect(content).not_to include(".send(")
      expect(content).to include("Current.customer_id || @page.customer_id")
    end
  end

  describe "prefill value slugs are rendered as Ruby string literals" do
    it "escapes a hostile property_slug so page_prefill_value cannot inject code" do
      payload = 'name#{system("id")}'
      entity = create(:entity, customer: tenant_a, property_schema: [{ "name_slug" => "name", "type" => "String" }].to_json)
      page = create(:page, customer: tenant_a, entity: entity)
      content = described_class.new(page).send(:generate_form_field, {
        "id" => "f1",
        "field_type" => "text",
        "html_type" => "text",
        "property_slug" => payload,
        "label" => "Name"
      })

      expect(content).to include("page_prefill_value(")
      expect(content).not_to include('#{system("id")}')
      expect(content).to include('\#{system(\"id\")}')
    end
  end

  describe "identity fields" do
    def identity_field(key, html_type: nil)
      html = html_type || (key == "email" ? "email" : "text")
      { "id" => "id_#{key}", "field_type" => html, "html_type" => html,
        "property_slug" => key, "source" => "identity", "label" => key.humanize }
    end

    it "names an identity email field identity[email] and uses the email component" do
      entity = create(:entity, customer: tenant_a, property_schema: [{ "name_slug" => "name", "type" => "String" }].to_json)
      page = create(:page, customer: tenant_a, entity: entity)
      content = described_class.new(page).send(:generate_form_field, identity_field("email", html_type: "text"))

      expect(content).to include("identity[email]")
      expect(content).to include("FormFields::EmailFieldComponent")
      expect(content).not_to include('field_name: "entity[email]"')
    end

    it "emits a hidden _continuation field that reads @page_continuation at render time" do
      entity = create(:entity, customer: tenant_a, property_schema: [{ "name_slug" => "name", "type" => "String" }].to_json)
      page = create(:page, customer: tenant_a, entity: entity, configuration_json: {
        "pages" => [{
          "id" => "p1",
          "fields" => [
            { "id" => "f1", "field_type" => "text", "html_type" => "text",
              "property_slug" => "name", "label" => "Name" }
          ]
        }]
      })
      content = described_class.new(page).generate

      expect(content).to include("hidden_field_tag :_page_id, @page.id")
      expect(content).to include("hidden_field_tag :_continuation, @page_continuation if @page_continuation.present?")
      expect(content).not_to match(/hidden_field_tag :_continuation, ["']/)
      expect(content).to include("hidden_field_tag :_run, @page_run_token if @page_run_token.present?")
      expect(content).to include("render Pages::LockedInputsComponent.new(page: @page, bindings: @page_bindings) if @page_bindings.present?")
    end

    it "reads the journey's progress, step actions and preview key from ivars in every presentation" do
      entity = create(:entity, customer: tenant_a, property_schema: [{ "name_slug" => "name", "type" => "String" }].to_json)
      step = ->(id) { { "id" => id, "fields" => [{ "id" => "f_#{id}", "html_type" => "text", "property_slug" => "name", "label" => "Name" }] } }
      single = create(:page, customer: tenant_a, entity: entity, configuration_json: { "pages" => [step.call("p1")] })
      wizard = create(:page, customer: tenant_a, entity: entity, configuration_json: { "pages" => [step.call("p1"), step.call("p2")] })

      [described_class.new(single).generate, described_class.new(wizard).generate,
       described_class.new(single, presentation: :entry).generate].each do |content|
        expect(content.scan("render Journeys::ProgressComponent.new(journey: @journey, current_key: @journey_step&.key) if @journey").size).to eq(1)
        expect(content.scan("extra_action: Journeys::StepActionsComponent.for(@journey_step)").size).to eq(1)
        expect(content).to include("hidden_field_tag :_journey, @journey_start_key if @journey_start_key.present?")
      end
      wizard_content = described_class.new(wizard).generate
      expect(wizard_content.index("Journeys::ProgressComponent")).to be < wizard_content.index("wizard.with_step")
    end

    it "wraps only declared input fields in a page_input_bound? guard" do
      entity = create(:entity, customer: tenant_a, property_schema: [{ "name_slug" => "name", "type" => "String" },
                                                                     { "name_slug" => "owner", "type" => "String" }].to_json)
      page = build(:page, customer: tenant_a, entity: entity, configuration_json: {
        "form_settings" => { "inputs" => [{ "field" => "owner", "entity_id" => "1" }] },
        "pages" => [{ "id" => "p1", "fields" => [
          { "id" => "f1", "html_type" => "text", "property_slug" => "name", "label" => "Name" },
          { "id" => "f2", "html_type" => "text", "property_slug" => "owner", "label" => "Owner" }
        ] }]
      })
      content = described_class.new(page).generate

      expect(content.scan("page_input_bound?").size).to eq(1)
      expect(content).to match(/<% unless page_input_bound\?\("owner"\) %>\s*<div data-field-id="f2">/)
    end

    it "renders identity first_name as identity[first_name] on a public page" do
      entity = create(:entity, customer: tenant_a, property_schema: [{ "name_slug" => "name", "type" => "String" }].to_json)
      page = create(:page, :for_public, customer: tenant_a, entity: entity, configuration_json: {
        "pages" => [{ "id" => "p1", "fields" => [identity_field("first_name")] }]
      })
      content = described_class.new(page).generate

      expect(content).to include("identity[first_name]")
    end
  end
end
