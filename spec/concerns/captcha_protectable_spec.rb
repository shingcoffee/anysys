# frozen_string_literal: true

require "rails_helper"

RSpec.describe CaptchaProtectable, type: :controller do
  controller(ApplicationController) do
    include CaptchaProtectable

    attr_accessor :page_double

    before_action :assign_page, only: :submit

    protect_with_captcha only: :submit, action: :page_submit
    protect_with_captcha only: :sign_up, action: :sign_up, fail: :closed

    def submit  = head(:ok)
    def sign_up = head(:ok)

    private

    def assign_page
      @page = page_double
    end
  end

  before do
    routes.draw { post "submit" => "anonymous#submit"; post "sign_up" => "anonymous#sign_up" }
    allow(controller).to receive(:current_customer_id).and_return(customer.id)
    # Bypass other feature-module before_action hooks (e.g. Authentication's
    # session enforcement) so we can isolate CaptchaProtectable behaviour.
    allow(controller).to receive(:run_feature_module_before_request)
    controller.page_double = page
  end

  let_it_be(:customer) { create(:customer) }
  let!(:fm) { find_or_create_feature_module!("captcha", name: "Captcha") }
  let!(:assignment) { ensure_customer_feature_module(customer, fm, status: :active, configuration: "{}") }
  let(:page)            { instance_double(Page, captcha_enabled?: true) }

  def stub_verify(outcome, fail_policy: "open")
    allow(Captcha::Activities::Verify).to receive(:call).and_return(
      instance_double(Captcha::Activities::Verify::Result,
                       passed?: outcome == :success,
                       blocked_hard?: %i[invalid replayed].include?(outcome),
                       disabled?: outcome == :disabled,
                       fail_policy: fail_policy,
                       outcome: outcome)
    )
  end

  describe "#captcha_required_for_request?" do
    it "is false when the captcha module is not enabled for the customer" do
      assignment.update!(status: :suspended)
      expect(Captcha::Activities::Verify).not_to receive(:call)
      post :submit
      expect(response).to have_http_status(:ok)
    end

    it "is false for :page_submit when the page has captcha disabled" do
      allow(page).to receive(:captcha_enabled?).and_return(false)
      expect(Captcha::Activities::Verify).not_to receive(:call)
      post :submit
      expect(response).to have_http_status(:ok)
    end

    it "is true for :page_submit when module enabled and page has captcha enabled" do
      stub_verify(:success)
      post :submit
      expect(Captcha::Activities::Verify).to have_received(:call)
    end

    it "is true for a non-page_submit action regardless of @page (e.g. :sign_up)" do
      stub_verify(:success)
      post :sign_up
      expect(Captcha::Activities::Verify).to have_received(:call)
    end

    context "when action is :sign_up and current_customer_id is blank" do
      before { allow(controller).to receive(:current_customer_id).and_return(nil) }

      it "does not call Verify when ProviderSettings.active is nil" do
        allow(Captcha::ProviderSettings).to receive(:active).and_return(nil)
        expect(Captcha::Activities::Verify).not_to receive(:call)
        post :sign_up
        expect(response).to have_http_status(:ok)
      end

      it "calls Verify when a configured enabled settings row exists" do
        Captcha::Providers::Aliyun
        create(:captcha_provider_settings, enabled: true)
        stub_verify(:success)
        post :sign_up
        expect(Captcha::Activities::Verify).to have_received(:call)
      end

      it "treats :sign_in and :password_reset the same as :sign_up" do
        allow(Captcha::ProviderSettings).to receive(:active).and_return(nil)
        expect(controller.send(:captcha_required_for_request?, :sign_in)).to be(false)
        expect(controller.send(:captcha_required_for_request?, :password_reset)).to be(false)

        allow(Captcha::ProviderSettings).to receive(:active).and_return(instance_double(Captcha::ProviderSettings))
        expect(controller.send(:captcha_required_for_request?, :sign_in)).to be(true)
        expect(controller.send(:captcha_required_for_request?, :password_reset)).to be(true)
      end
    end
  end

  context "when the activity returns :success" do
    before { stub_verify(:success) }

    it "permits the request" do
      post :submit
      expect(response).to have_http_status(:ok)
    end
  end

  context "when the activity returns :disabled" do
    before { stub_verify(:disabled) }

    it "always permits the request, even under a fail-closed override" do
      post :sign_up
      expect(response).to have_http_status(:ok)
    end
  end

  %i[invalid replayed].each do |outcome|
    context "when the activity returns :#{outcome} (hard block)" do
      before do
        stub_verify(outcome)
        allow(controller).to receive(:render) { |*args|
          opts = args.last.is_a?(Hash) ? args.last : {}
          controller.head(opts[:status] || :unprocessable_entity)
        }
      end

      it "sets @captcha_failed, flashes an alert, and renders 422" do
        post :submit
        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash.now[:alert]).to be_present
        expect(controller.instance_variable_get(:@captcha_failed)).to eq(true)
      end

      it "hard-blocks even under a fail-open policy (no fail: override)" do
        post :submit
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  %i[unreachable configuration_error].each do |outcome|
    context "when the activity returns :#{outcome} (fail-open eligible) and no fail override" do
      before { stub_verify(outcome) }

      it "permits the request under the default fail-open policy" do
        post :submit
        expect(response).to have_http_status(:ok)
      end

      it "shows the fail-open notice flash" do
        post :submit
        expect(flash.now[:notice]).to be_present
      end
    end

    context "when the activity returns :#{outcome} and fail: :closed is configured for the action" do
      before do
        stub_verify(outcome)
        allow(controller).to receive(:render) { |*args|
          opts = args.last.is_a?(Hash) ? args.last : {}
          controller.head(opts[:status] || :unprocessable_entity)
        }
      end

      it "blocks the request (fail-closed override wins over the platform default)" do
        post :sign_up
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when the activity returns :#{outcome} and the active provider's settings are fail_closed" do
      before do
        stub_verify(outcome, fail_policy: "closed")
        allow(controller).to receive(:render) { |*args|
          opts = args.last.is_a?(Hash) ? args.last : {}
          controller.head(opts[:status] || :unprocessable_entity)
        }
      end

      it "blocks the request (no per-action override, platform default is fail-closed)" do
        post :submit
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
