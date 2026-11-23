# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::PlanFormComponent, type: :component do
  let(:new_plan) { Billing::Plan.new }

  let(:persisted_plan) do
    plan = Billing::Plan.new(
      code: "pro-monthly", name: "Pro Monthly",
      amount_usd: 29.00, amount_cny: 199.00,
      interval: "monthly", trial_days: 0,
      active: true, is_default: false, position: 1
    )
    plan.id = 1
    plan.instance_variable_set(:@new_record, false)
    plan
  end

  before do
    stub_helpers = double(
      "helpers",
      admin_maintenance_platform_billing_plans_path: "/81721200/admin/maintenance/platform/billing/plans",
      admin_maintenance_platform_billing_plan_path:  "/81721200/admin/maintenance/platform/billing/plans/1",
      protect_against_forgery?: false
    )
    allow_any_instance_of(described_class).to receive(:helpers).and_return(stub_helpers)
  end

  def build_component(plan, customer_id: "81721200", **opts)
    described_class.new(plan: plan, customer_id: customer_id, **opts)
  end

  def render_form(plan, **opts)
    render_inline(build_component(plan, **opts))
  end

  describe "new plan form" do
    before { render_form(new_plan) }

    it "renders the sectioned layout" do
      expect(page).to have_css("h2", text: "Plan details")
      expect(page).to have_css("h2", text: "Pricing")
      expect(page).to have_css("h2", text: "Availability")
    end

    it "renders Create Plan submit button" do
      expect(page).to have_button("Create Plan")
      expect(page).to have_link("Cancel")
    end

    it "puts Cancel and Create Plan in the last panel footer" do
      expect(page).to have_css("footer a.btn-secondary", text: "Cancel")
      expect(page).to have_css("footer input.btn-primary[value='Create Plan']")
    end

    it "renders required fields" do
      expect(page).to have_field("billing_plan[name]")
      expect(page).to have_field("billing_plan[amount_usd]")
      expect(page).to have_field("billing_plan[amount_cny]")
      expect(page).to have_field("billing_plan[trial_days]")
    end

    it "renders interval select and numeric price, trial, and order fields" do
      expect(page).to have_select("billing_plan[interval]")
      expect(page).to have_css('input[type="number"][name="billing_plan[amount_usd]"][min="0"][step="0.01"]')
      expect(page).to have_css('input[type="number"][name="billing_plan[amount_cny]"]')
      expect(page).to have_css('input[type="number"][name="billing_plan[trial_days]"]')
      expect(page).to have_css('input[type="number"][name="billing_plan[position]"]')
      expect(page).not_to have_text("retain their purchased price and limit snapshots")
    end

    it "renders active and is_default checkboxes" do
      expect(page).to have_field("billing_plan[active]")
      expect(page).to have_field("billing_plan[is_default]")
    end
  end

  describe "edit plan form" do
    before { render_form(persisted_plan) }

    it "renders Update Plan submit button" do
      expect(page).to have_button("Update Plan")
    end

    it "disables the code field" do
      code_field = page.find_field("billing_plan[code]", disabled: true)
      expect(code_field).to be_disabled
    end

    it "shows cannot-change code note and the snapshot note for an existing plan" do
      expect(page).to have_text("Code cannot be changed after creation.")
      expect(page).to have_text("retain their purchased price and limit snapshots")
    end
  end

  describe "limit inputs" do
    let(:plan) { Billing::Plan.create!(code: "pro", name: "Pro", amount_usd: 29.00, amount_cny: 199.00, interval: "monthly") }
    let(:flow) { Billing::CountableItem.create!(key: "flowchart", label: "Flowcharts", enabled: true) }

    before { Billing::PlanLimit.create!(billing_plan_id: plan.id, item_key: "flowchart", limit_value: 7) }

    it "renders a limit input per item pre-filled with the current value" do
      render = render_form(plan, items: [flow], customer_id: "1")
      input = render.css('input[name="billing_plan[limits][flowchart]"]').first
      expect(input).to be_present
      expect(input["type"]).to eq("number")
      expect(input["min"]).to eq("-1")
      expect(input["value"]).to eq("7")
      expect(input["placeholder"]).to eq("Unlimited")
      expect(render.text).to include("Leave blank for unlimited. Enter a whole number to cap usage.")
    end

    it "shows a muted unit suffix when the countable item has a unit" do
      flow.update!(unit: "charts")
      render_form(plan, items: [flow.reload], customer_id: "1")
      expect(page).to have_css("span.text-text-muted", text: "charts")
      expect(page).to have_css('input[name="billing_plan[limits][flowchart]"].pr-16')
    end
  end

  describe "#item_unit" do
    it "returns a present unit and ignores blank or missing units" do
      component = build_component(new_plan)
      expect(component.item_unit(double(unit: " emails "))).to eq("emails")
      expect(component.item_unit(double(unit: "  "))).to be_nil
      expect(component.item_unit(double(key: "page"))).to be_nil
    end
  end

  describe "form_method" do
    it "returns :post for new plan" do
      expect(build_component(new_plan).form_method).to eq(:post)
    end

    it "returns :patch for persisted plan" do
      expect(build_component(persisted_plan).form_method).to eq(:patch)
    end
  end

  describe "interval_options" do
    it "includes monthly and yearly" do
      codes = build_component(new_plan).interval_options.map(&:last)
      expect(codes).to include("monthly", "yearly")
    end
  end

  it "renders raw submitted prices, limits and field errors from Reform without mutating the plan" do
    form = Billing::Contracts::Plan.new(new_plan)
    form.amount_usd = "abc.12"
    form.trial_days = "not-days"
    form.limits = { "page" => "many" }
    form.errors.add(:amount_usd, "is invalid")
    form.errors.add(:limits, "is invalid")
    item = double(key: "page", label: "Pages")
    render_form(new_plan, form: form, items: [item])
    expect(page).to have_field("billing_plan[amount_usd]", with: "abc.12")
    expect(page).to have_field("billing_plan[trial_days]", with: "not-days")
    expect(page).to have_field("billing_plan[limits][page]", with: "many")
    expect(page).to have_css('input[aria-invalid="true"][aria-describedby="billing_plan_amount_usd_error"]')
    expect(page).to have_css('input[id="billing_plan_limits_page"][aria-invalid="true"]')
    expect(page).not_to have_text("retain their purchased price and limit snapshots")
    expect(new_plan.amount_usd).not_to eq("abc.12")
  end
end
