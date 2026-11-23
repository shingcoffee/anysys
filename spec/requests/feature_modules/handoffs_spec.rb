# frozen_string_literal: true

require "rails_helper"

# The framework hop every page → module handoff goes through
# (/:customer_id/handoff): Turbo breakout, the generic user_fillable entry
# step, then the module's entry_path. Driven by a real page submission so the
# invocation lives in the session exactly as in production. Handoff is asked
# for by a `hand_off_to_module` step on the page's bound flowchart.
RSpec.describe "FeatureModules::Handoffs", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:entity) { create(:entity, customer: customer) }
  let(:handoff_path) { "/#{customer.id}/handoff" }
  let(:turbo_headers) do
    { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml",
      "X-Turbo-Request-Id" => SecureRandom.uuid }
  end

  let(:demo_registration) do
    Class.new(FeatureModules::BaseModule) do
      def self.module_key = "demo_handoff"
      def self.module_name = "Demo"
      def self.provision!(_c) = nil
      entry_path { |c| "/#{c.id}/demo/start" }
      input_contract do
        property :amount, type: :number, validates: { presence: true, numericality: { greater_than: 0 } }
        property :phone,  type: :string, source: :user_fillable, validates: { presence: true }
        property :plan,   type: :enum,   source: :user_fillable, validates: { inclusion: { in: %w[basic pro], allow_blank: true } }
      end
    end
  end
  let(:registrations) { { "demo_handoff" => demo_registration } }

  let!(:demo_module) do
    enable_module!("demo_handoff", customer, name: "Demo").tap { |fm| fm.update!(handoff_enabled: true) }
  end

  before do
    allow_any_instance_of(FeatureModules::Module).to receive(:registration_class) do |record|
      registrations.fetch(record.key) { "FeatureModules::#{record.key.camelize}::Registration".constantize }
    end
    I18n.backend.store_translations(:en, feature_modules: { demo_handoff: { handoff_entry: {
      fields: { phone: { label: "Phone" }, plan: { label: "Plan" } }
    } } })
  end

  after { I18n.reload! }

  def build_page(module_key:, input:)
    Current.set(customer: customer) do
      create(:page, :for_member, :for_public, :launched, customer: customer, entity: entity,
             configuration: {
               metadata: { entity_id: entity.id, entity_name: entity.name },
               fields: []
             }.to_json)
    end.tap do |page|
      bind_page_flowchart(page, steps: [{
        "action" => "hand_off_to_module",
        "config" => { "moduleKey" => module_key, "input" => input }
      }])
    end
  end

  def hand_off_to_demo
    page = build_page(module_key: "demo_handoff", input: [{ "key" => "amount", "value" => "12.5" }])
    post "/#{customer.id}/page/#{page.public_uuid}"
    expect(response).to redirect_to(handoff_path)
  end

  def invocation = session[:feature_module_invocation].with_indifferent_access

  context "when the module declares user_fillable inputs" do
    before { hand_off_to_demo }

    it "begins the invocation even though a required user_fillable input is still blank" do
      expect(invocation).to include(module_key: "demo_handoff", awaiting_input: true)
      expect(invocation[:input]).to include(amount: 12.5)
    end

    it "breaks a Turbo-driven visit out to a top-level load" do
      get handoff_path, headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include('<meta name="turbo-visit-control" content="reload">')
      expect(response.body).not_to include('name="handoff[phone]"')
    end

    it "renders the generic entry step for the user_fillable fields only, outside Turbo Drive" do
      get handoff_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<meta name="turbo-visit-control" content="reload">')
      expect(response.body).to include('name="handoff[phone]"', 'name="handoff[plan]"', "Phone")
      expect(response.body).not_to include('name="handoff[amount]"')
      expect(response.body).to include('data-turbo="false"')
      expect(response.body).to include(I18n.t("feature_modules.handoff_entry.title"))
    end

    it "merges the end user's input, ignores forged author_only values, and enters the module" do
      patch handoff_path, params: { handoff: { phone: "13800000000", plan: "PRO", amount: "0.01" } }

      expect(response).to redirect_to("/#{customer.id}/demo/start")
      expect(invocation[:awaiting_input]).to be(false)
      expect(invocation[:input]).to include(amount: 12.5, phone: "13800000000", plan: "pro")
    end

    it "re-renders the entry step with errors and keeps the module closed when input is invalid" do
      patch handoff_path, params: { handoff: { phone: "", plan: "gold" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Phone can&#39;t be blank")
      expect(invocation[:awaiting_input]).to be(true)
    end

    it "handles a malformed (non-hash) handoff param without a 500" do
      patch handoff_path, params: { handoff: "not-a-hash" }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "goes straight to the module once the input has been supplied" do
      patch handoff_path, params: { handoff: { phone: "13800000000" } }

      get handoff_path
      expect(response).to redirect_to("/#{customer.id}/demo/start")

      patch handoff_path, params: { handoff: { phone: "overwrite" } }
      expect(response).to redirect_to("/#{customer.id}/demo/start")
      expect(invocation[:input][:phone]).to eq("13800000000")
    end

    it "renders for an Alipay in-app browser that Rails :modern would 406" do
      get handoff_path, headers: {
        "HTTP_USER_AGENT" => "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 AliApp(AP/10.5.36.6000) AlipayClient/10.5.36.6000"
      }
      expect(response).to have_http_status(:ok)
    end

    it "refuses the invocation from another tenant's URL" do
      other = create(:customer)
      get "/#{other.id}/handoff"
      expect(response).to have_http_status(:forbidden)
    end
  end

  context "when the module needs no end-user input" do
    let(:demo_registration) do
      Class.new(FeatureModules::BaseModule) do
        def self.module_key = "demo_handoff"
        def self.module_name = "Demo"
        def self.provision!(_c) = nil
        entry_path { |c| "/#{c.id}/demo/start" }
        input_contract { property :amount, type: :number, validates: { presence: true } }
      end
    end

    before { hand_off_to_demo }

    it "redirects a top-level visit straight to the module's entry_path" do
      expect(invocation[:awaiting_input]).to be(false)
      get handoff_path
      expect(response).to redirect_to("/#{customer.id}/demo/start")
    end

    it "still breaks a Turbo-driven visit out before entering the module" do
      get handoff_path, headers: turbo_headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<meta name="turbo-visit-control" content="reload">')
    end
  end

  it "bounces to the customer home without an active invocation" do
    get handoff_path
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq(I18n.t("feature_modules.handoff.no_active_request"))
  end

  describe "a page handing off to the Payment module" do
    let!(:payment_module) do
      enable_module!("payment", customer, name: "Payments").tap { |fm| fm.update!(handoff_enabled: true) }
    end

    it "collects the payer note with the payment copy, then materializes the order on entry" do
      page = build_page(module_key: "payment", input: [
        { "key" => "amount", "value" => "1.0" },
        { "key" => "currency", "value" => '"CNY"' },
        { "key" => "subject", "value" => '"Course fee"' }
      ])
      post "/#{customer.id}/page/#{page.public_uuid}"
      expect(response).to redirect_to(handoff_path)

      get handoff_path
      expect(response.body).to include(I18n.t("comp_payments.handoff_entry.title"), 'name="handoff[body]"')

      get "/#{customer.id}/payments/checkout/start"
      expect(response).to redirect_to(handoff_path)

      patch handoff_path, params: { handoff: { body: "Room 101" } }
      expect(response).to redirect_to("/#{customer.id}/payments/checkout/start")

      expect { follow_redirect! }.to change(Payments::Order, :count).by(1)
      order = Payments::Order.unscoped_by_tenant.find_by!(customer_id: customer.id)
      expect(order).to have_attributes(amount: 1.0, currency: "CNY", subject: "Course fee", body: "Room 101")
    end
  end
end
