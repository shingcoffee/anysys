# frozen_string_literal: true

require "rails_helper"

# Area (d) — /:cid/admin/maintenance/platform/module_settings/billing/settings
# Tests: owner-only authorization + show/edit/update happy paths.
# Specifically verifies comma-separated dunning_schedule parsing.
RSpec.describe "admin/maintenance/platform/billing/settings", type: :request do
  let!(:platform_owner) { find_or_create_platform_owner }
  let!(:platform_cid)   { ensure_platform_customer.id }

  let!(:regular_customer) { create(:customer) }
  let!(:regular_admin)    { create(:user, :admin, customer: regular_customer) }
  let!(:regular_member)   { create(:user, :member, customer: regular_customer) }

  # Ensure a clean settings singleton for each test
  before { Billing::Settings.delete_all }

  # Baseline valid settings payload; each update example merges only the
  # attributes it exercises (kept positional to avoid keyword-arg swallowing).
  let(:base_settings) do
    { tax_rate_bps: 0, collection_mode: "manual", grace_period_days: 7,
      trial_ending_notice_days: 3, dunning_schedule: "" }
  end

  def update_billing_settings(overrides = {})
    patch admin_maintenance_platform_billing_settings_path(platform_cid),
          params: { billing_settings: base_settings.merge(overrides) }
  end

  let(:guard_path) { admin_maintenance_platform_billing_settings_path(platform_cid) }

  it_behaves_like "a platform-owner-guarded GET"
  it_behaves_like "a platform-owner-guarded request", :patch

  describe "GET edit auth" do
    let(:guard_path) { edit_admin_maintenance_platform_billing_settings_path(platform_cid) }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "regular admin (non-owner)" do
    before { sign_in regular_admin }

    it "is blocked on GET show" do
      get admin_maintenance_platform_billing_settings_path(regular_customer.id)
      expect(response).not_to have_http_status(:ok)
    end

    it "is blocked on PATCH update" do
      patch admin_maintenance_platform_billing_settings_path(regular_customer.id),
            params: { billing_settings: { tax_rate_bps: 100 } }
      expect(response).not_to have_http_status(:ok)
    end
  end

  describe "member access" do
    before { sign_in regular_member }

    it "is blocked on GET show" do
      get admin_maintenance_platform_billing_settings_path(regular_customer.id)
      expect(response).not_to have_http_status(:ok)
    end
  end

  # -------------------------------------------------------------------------
  # Happy paths — platform owner
  # -------------------------------------------------------------------------
  describe "platform owner" do
    before { sign_in platform_owner }

    describe "GET show and edit" do
      it "returns 200 for each page" do
        [
          admin_maintenance_platform_billing_settings_path(platform_cid),
          edit_admin_maintenance_platform_billing_settings_path(platform_cid)
        ].each do |path|
          get path
          expect(response).to have_http_status(:ok)
        end
      end
    end

    describe "PATCH update" do
      it "persists tax_rate_bps updates and redirects to show" do
        update_billing_settings(tax_rate_bps: 500, grace_period_days: 5, dunning_schedule: "1, 3, 7")
        expect(response).to have_http_status(:redirect)
        expect(response.location).to include(
          admin_maintenance_platform_billing_settings_path(platform_cid)
        )
        settings = Billing::Settings.current
        expect(settings.tax_rate_bps).to eq(500)
      end

      it "parses comma-separated dunning_schedule into integer array" do
        update_billing_settings(dunning_schedule: "2, 5, 10")
        expect(response).to have_http_status(:redirect)
        settings = Billing::Settings.current
        expect(settings.dunning_schedule).to eq([2, 5, 10])
      end

      it "handles dunning_schedule with extra spaces" do
        update_billing_settings(dunning_schedule: " 1 , 3 , 7 ")
        expect(response).to have_http_status(:redirect)
        settings = Billing::Settings.current
        expect(settings.dunning_schedule).to eq([1, 3, 7])
      end

      it "handles empty dunning_schedule string (stores empty array)" do
        update_billing_settings
        expect(response).to have_http_status(:redirect)
        settings = Billing::Settings.current
        expect(settings.dunning_schedule).to eq([])
      end

      it "does not persist with invalid collection_mode fails validation" do
        # The update fails at model validation — no redirect occurs
        update_billing_settings(collection_mode: "invalid_mode")
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "does not persist a non-numeric dunning_schedule as zero-day retries" do
        update_billing_settings(dunning_schedule: "1, soon, 7")
        expect(response).to have_http_status(:unprocessable_entity)
        expect(Billing::Settings.current.dunning_schedule).to eq([1, 3, 7])
      end

      it "does not persist a zero dunning offset" do
        update_billing_settings(dunning_schedule: "1, 0, 7")
        expect(response).to have_http_status(:unprocessable_entity)
        expect(Billing::Settings.current.dunning_schedule).to eq([1, 3, 7])
      end

      ["1,,7", "1,3,", "3,1", "1,1", "1.5,3", "-1,3", "+1,3", "01,3", "1_0,30"].each do |schedule|
        it "does not coerce or discard invalid schedule #{schedule.inspect}" do
          update_billing_settings(dunning_schedule: schedule)
          expect(response).to have_http_status(:unprocessable_entity)
          expect(Billing::Settings.current.dunning_schedule).to eq([1, 3, 7])
        end
      end

      it "does not permit the unused global gateway_provider" do
        expect(Billing::Activities::UpdateSettings).to receive(:call).with(
          settings: an_instance_of(Billing::Settings), params: hash_excluding("gateway_provider")
        ).and_return(Billing::Result.new(status: :saved))
        update_billing_settings(gateway_provider: "forged")
        expect(response).to have_http_status(:see_other)
      end

      it "preserves the failing Reform form and exact submitted schedule text" do
        form = Billing::Contracts::Settings.new(Billing::Settings.current)
        form.validate(base_settings.merge(dunning_schedule: "1, soon, 7"))
        expect(Billing::Activities::UpdateSettings).to receive(:call).with(
          settings: an_instance_of(Billing::Settings), params: hash_including("dunning_schedule" => [1, "soon", 7])
        ).and_return(Billing::Result.new(status: :invalid, form: form, errors: form.errors.messages))
        expect_any_instance_of(Admin::Maintenance::Platform::Billing::SettingsController).to receive(:render)
          .with(:edit, status: :unprocessable_entity).and_wrap_original do |original, *args, **kwargs|
            expect(original.receiver.instance_variable_get(:@form)).to equal(form)
            expect(original.receiver.instance_variable_get(:@submitted_dunning_schedule)).to eq("1, soon, 7")
            original.call(*args, **kwargs)
          end
        update_billing_settings(dunning_schedule: "1, soon, 7")
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
