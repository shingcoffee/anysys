# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::ExitResolver do
  let_it_be(:customer) { create(:customer) }
  let!(:feature_module) { create(:feature_module, :handoffable, key: "demo", name: "Demo") }
  let!(:customer_feature_module) do
    create(:customer_feature_module,
           customer: customer, feature_module: feature_module,
           status: :active, configuration: {}.to_json)
  end

  before { Current.customer = customer }
  after  { Current.customer = nil }

  def resolve(target)
    described_class.call(customer: customer, module_key: "demo", session_exit_target: target)
  end

  describe "kind: 'url'" do
    it "returns the url when scheme is https" do
      expect(resolve("kind" => "url", "url" => "https://acme.test/thanks")).to eq("https://acme.test/thanks")
    end

    it "returns the url when scheme is http" do
      expect(resolve("kind" => "url", "url" => "http://acme.test")).to eq("http://acme.test")
    end

    it "skips a javascript: scheme and falls through to customer-home fallback" do
      expect(resolve("kind" => "url", "url" => "javascript:alert(1)")).to eq("/#{customer.id}/admin/dashboard")
    end
  end

  describe "kind: 'page'" do
    it "returns the public page URL when the page is published" do
      page = create(:page, customer: customer, launched: true)
      expect(resolve("kind" => "page", "page_id" => page.id)).to eq("/#{customer.id}/page/#{page.public_uuid}")
    end

    it "returns the editor page URL when the page is not published" do
      page = create(:page, customer: customer, launched: false)
      expect(resolve("kind" => "page", "page_id" => page.id)).to eq("/#{customer.id}/admin/maintenance/pages/#{page.id}")
    end

    it "skips when the page belongs to another customer" do
      other = create(:customer)
      other_page = create(:page, customer: other, launched: true)
      expect(resolve("kind" => "page", "page_id" => other_page.id)).to eq("/#{customer.id}/admin/dashboard")
    end

    it "returns the public URL for a launched shared page" do
      page = create(:page, :shared, launched: true)
      expect(resolve("kind" => "page", "page_id" => page.id)).to eq("/#{customer.id}/page/#{page.public_uuid}")
    end
  end

  describe "kind: 'flowchart'" do
    it "falls through — flowchart catch-all URLs were removed" do
      entity = create(:entity, customer: customer, name: "Orders")
      create(:flowchart, customer: customer, uuid: "abc123")
      expect(resolve("kind" => "flowchart", "flowchart_uuid" => "abc123", "entity_id" => entity.id))
        .to eq("/#{customer.id}/admin/dashboard")
    end
  end

  describe "kind: 'route'" do
    it "resolves an allowlisted route name" do
      expect(resolve("kind" => "route", "name" => "customer_home")).to eq("/#{customer.id}/admin/dashboard")
    end

    it "skips a non-allowlisted route and falls through" do
      expect(resolve("kind" => "route", "name" => "admin_root")).to eq("/#{customer.id}/admin/dashboard")
    end
  end

  describe "fallback chain" do
    it "falls back to customer-level override when session target is absent" do
      page = create(:page, customer: customer, launched: true)
      customer_feature_module.update!(configuration: { exit_landing_page: { kind: "page", page_id: page.id } }.to_json)

      expect(resolve(nil)).to eq("/#{customer.id}/page/#{page.public_uuid}")
    end

    it "ignores a saved customer Return URL while handoff is disabled and restores it when enabled" do
      customer_feature_module.merge_configuration!(exit_landing_page: { kind: "url", url: "https://demo.test/thanks" })
      feature_module.update!(handoff_enabled: false)

      expect(resolve(nil)).to eq("/#{customer.id}/admin/dashboard")

      feature_module.update!(handoff_enabled: true)
      expect(resolve(nil)).to eq("https://demo.test/thanks")
    end

    it "ignores the customer Return URL when that customer's assignment is suspended" do
      customer_feature_module.merge_configuration!(exit_landing_page: { kind: "url", url: "https://demo.test/thanks" })
      customer_feature_module.update!(status: :suspended)

      expect(resolve(nil)).to eq("/#{customer.id}/admin/dashboard")
    end

    it "falls back to module default_exit when no session target and no customer override" do
      registration = class_double(FeatureModules::BaseModule,
                                  default_exit_config: { kind: "url", url: "https://mod.test" })
      allow(feature_module).to receive(:registration_class).and_return(registration)
      allow(FeatureModules::Module).to receive(:find_by).with(key: "demo").and_return(feature_module)

      expect(resolve(nil)).to eq("https://mod.test")
    end

    it "falls back to /:customer_id/admin when all other steps fail" do
      expect(resolve(nil)).to eq("/#{customer.id}/admin/dashboard")
    end

    context "without an object configuration" do
      let(:registration) do
        class_double(FeatureModules::BaseModule,
                     default_exit_config: { kind: "url", url: "https://mod.test/default" })
      end

      before do
        allow(feature_module).to receive(:registration_class).and_return(registration)
        allow(FeatureModules::Module).to receive(:find_by).with(key: "demo").and_return(feature_module)
      end

      it "uses the registered default when customer settings have never been saved" do
        customer_feature_module.update_column(:configuration, nil)

        expect(resolve(nil)).to eq("https://mod.test/default")
      end

      it "uses customer home when settings are missing and the registered default cannot resolve" do
        customer_feature_module.update_column(:configuration, nil)
        allow(registration).to receive(:default_exit_config).and_return(kind: "route", name: "not_allowlisted")

        expect(resolve(nil)).to eq("/#{customer.id}/admin/dashboard")
      end

      it "ignores non-object JSON and uses the registered default" do
        ["null", "[]", '[{"exit_landing_page":{"kind":"url","url":"https://ignored.test"}}]',
         '"exit_landing_page"', "42", "true", "false"].each do |configuration|
          customer_feature_module.update_column(:configuration, configuration)

          expect(resolve(nil)).to eq("https://mod.test/default")
        end
      end

      it "ignores non-object JSON and uses customer home when no default is registered" do
        allow(registration).to receive(:default_exit_config).and_return(nil)
        ["null", "[]", '"exit_landing_page"', "42", "true", "false"].each do |configuration|
          customer_feature_module.update_column(:configuration, configuration)

          expect(resolve(nil)).to eq("/#{customer.id}/admin/dashboard")
        end
      end
    end

    it "ignores bad JSON in customer_feature_module.configuration and continues chain" do
      customer_feature_module.update_column(:configuration, "not json")
      expect(resolve(nil)).to eq("/#{customer.id}/admin/dashboard")
    end
  end

  describe "resolve_url — URI edge cases" do
    it "returns nil (and falls through) for a URL that raises URI::InvalidURIError" do
      # URI.parse raises InvalidURIError on a URL with illegal characters
      expect(resolve("kind" => "url", "url" => "https://example.com/path with spaces"))
        .to eq("/#{customer.id}/admin/dashboard")
    end
  end

  describe "resolve_page — launched page without public_uuid" do
    it "returns the admin editor URL when page is launched but public_uuid is blank" do
      page = create(:page, customer: customer, launched: true)
      page.update_column(:public_uuid, nil)  # force blank after launch
      expect(resolve("kind" => "page", "page_id" => page.id))
        .to eq("/#{customer.id}/admin/maintenance/pages/#{page.id}")
    end
  end

  describe "the invocation's audience" do
    def resolve_for(audience, target)
      described_class.call(customer: customer, module_key: "demo", session_exit_target: target, audience: audience)
    end

    it "lands a member in the member area and a visitor on the site root" do
      expect(resolve_for("member", nil)).to eq("/#{customer.id}/member")
      expect(resolve_for("public", nil)).to eq("/")
      expect(resolve_for("admin", nil)).to eq("/#{customer.id}/admin/dashboard")
    end

    describe "kind: 'record'" do
      let(:entity) { create(:entity, customer: customer) }
      let(:entry) { create(:entity_entry, entity: entity, customer: customer, data: {}.to_json) }
      let(:target) { { "kind" => "record", "entity_id" => entity.id, "entry_id" => entry.id } }

      it "opens the record on the member surface for a member" do
        expect(resolve_for("member", target)).to eq("/#{customer.id}/member/entity_#{entity.id}/#{entry.id}")
      end

      it "opens the record in admin for an admin" do
        expect(resolve_for("admin", target)).to eq("/#{customer.id}/admin/entities/#{entity.id}/entries/#{entry.id}")
      end

      it "falls through for a visitor and for another tenant's record" do
        expect(resolve_for("public", target)).to eq("/")

        other = create(:customer)
        foreign = create(:entity_entry, entity: create(:entity, customer: other), customer: other, data: {}.to_json)
        expect(resolve_for("member", target.merge("entity_id" => foreign.entity_id, "entry_id" => foreign.id)))
          .to eq("/#{customer.id}/member")
      end
    end
  end
end
