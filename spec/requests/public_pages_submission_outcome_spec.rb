# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public page submission outcomes", type: :request do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other) { create(:customer) }
  let(:entity) { create(:entity, customer: customer) }

  def page_url(page)
    "/#{customer.id}/page/#{page.public_uuid}"
  end

  def build_page(body:, extra_form_settings: {}, launched: true)
    traits = %i[for_member for_public]
    page = Current.set(customer: customer) do
      create(:page, *traits,
             customer: customer,
             entity: entity,
             launched: launched,
             configuration: {
               form_settings: extra_form_settings,
               metadata: { entity_id: entity.id, entity_name: entity.name },
               fields: []
             }.to_json)
    end
    bind_page_flowchart(page, body: body)
    page
  end

  def write_outcome(hash)
    "ctx[:submission_outcome] = #{hash.inspect}\n          true"
  end

  describe "presets" do
    {
      "submitted" => :submitted,
      "saved" => :saved,
      "thank_you" => :thank_you
    }.each do |preset, key|
      it "flashes public_views.flash.outcomes.#{preset}" do
        page = build_page(body: write_outcome("preset" => preset, "flash" => "notice"))
        post page_url(page)
        expect(response).to redirect_to(page_url(page))
        expect(flash[:notice]).to eq(I18n.t("public_views.flash.outcomes.#{key}"))
      end
    end

    it "flashes a custom zh-CN message" do
      page = build_page(body: write_outcome(
        "preset" => "custom",
        "message" => { "en" => "Thanks", "zh-CN" => "报名成功。" },
        "flash" => "notice"
      ))
      post page_url(page), params: { locale: "zh-CN" }
      expect(response).to redirect_to("#{page_url(page)}?locale=zh-CN")
      expect(flash[:notice]).to eq("报名成功。")
    end
  end

  describe "post-submit destination" do
    it "returns to the form even when an outcome names another page" do
      target = Current.set(customer: customer) do
        create(:page, :for_member, :for_public, customer: customer, launched: true)
      end
      page = build_page(body: write_outcome(
        "preset" => "submitted",
        "flash" => "notice",
        "target" => { "type" => "page", "page_id" => target.id }
      ))
      post page_url(page)
      expect(response).to redirect_to(page_url(page))
      expect(flash[:notice]).to eq(I18n.t("public_views.flash.outcomes.submitted"))
    end
  end

  describe "flowchart handoff" do
    let!(:payment_fm) do
      fm = enable_module!("payment", customer, name: "Payments")
      fm.update!(handoff_enabled: true)
      fm
    end
    let!(:demo) { create(:feature_module, :handoffable, key: "demo_outcome", name: "Demo") }
    let!(:demo_assignment) do
      ensure_customer_feature_module(customer, demo, status: :active)
    end
    let(:registration) do
      Class.new(FeatureModules::BaseModule) do
        def self.module_key = "demo_outcome"
        def self.module_name = "Demo"
        def self.provision!(_c) = nil
        entry_path { |c| "/#{c.id}/demo/start" }
      end
    end

    before do
      allow_any_instance_of(FeatureModules::Module).to receive(:registration_class) do |record|
        if record.key == "demo_outcome"
          registration
        else
          "FeatureModules::#{record.key.camelize}::Registration".constantize
        end
      end
    end

    it "hands off from the flowchart step even when leftover after_submit handoff settings remain on the page" do
      page = build_page(
        extra_form_settings: {
          after_submit: "handoff",
          handoff: {
            module_key: "demo_outcome",
            input_mapping: {},
            exit_target: { kind: "url", url: "https://ok.test" }
          }
        },
        body: <<~RUBY
          FlowchartRuntime::Handoff.request(ctx, module_key: "payment",
                                            input: { "amount" => 10.0, "currency" => "CNY", "subject" => "Fee" })
        RUBY
      )

      post page_url(page)
      expect(response).to redirect_to("/#{customer.id}/handoff")
      expect(session[:feature_module_invocation][:module_key]).to eq("payment")
      expect(session[:feature_module_invocation][:input]).to include(amount: 10.0, currency: "CNY", subject: "Fee")
      expect(Payments::Order.count).to eq(0)
    end

    it "hands off to any module named in the flowchart outcome, not only payment" do
      page = build_page(
        body: <<~RUBY
          FlowchartRuntime::Handoff.request(ctx, module_key: "demo_outcome",
                                            input: { "note" => "from flowchart" })
        RUBY
      )

      post page_url(page)
      expect(response).to redirect_to("/#{customer.id}/handoff")
      expect(session[:feature_module_invocation][:module_key]).to eq("demo_outcome")
      expect(session[:feature_module_invocation][:input]).to include(note: "from flowchart")
    end
  end

  describe "refund of another tenant's payment" do
    it "rejects the refund and shows the translated code" do
      foreign = create(:payment, customer: other, status: "succeeded", amount: 5.00)
      expect(Payments::Gateway).not_to receive(:refund)
      page = build_page(body: "return FlowchartRuntime::Payments.refund(ctx, payment: #{foreign.id}, amount: 1.00)")

      post page_url(page)
      expect(response).to redirect_to(page_url(page))
      expect(flash[:alert]).to include(I18n.t("flowchart_runtime.errors.refund_payment.not_found"))
      expect(Payments::Refund.where(payment_id: foreign.id)).to be_empty
    end
  end
end
