# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::Presentation do
  let(:plan) { Billing::Plan.new(name: "Stored name", amount_usd: 29, active: true) }
  let(:form) { Billing::Contracts::Plan.new(plan) }
  let(:component) { Billing::Admin::PlanFormComponent.new(plan: plan, form: form, customer_id: 81721200) }

  it "reads submitted Reform properties without replacing invalid, nil, false or zero values" do
    form.amount_usd = "not-a-price"
    form.name = nil
    form.active = false
    form.trial_days = 0
    form.limits = { "page" => "many", "member" => 0 }

    expect(component.form_value(:amount_usd)).to eq("not-a-price")
    expect(component.form_value(:name)).to be_nil
    expect(component.form_value(:active)).to be(false)
    expect(component.form_value(:trial_days)).to eq(0)
    expect(component.form_value(:limits)).to eq("page" => "many", "member" => 0)
    expect(plan.name).to eq("Stored name")
    expect(plan.amount_usd).to eq(29)
    expect(plan.active).to be(true)
  end

  it "reads string and symbol fact keys without treating an absent key as a Hash method" do
    expect(component.fact({ page: 12 }, "page")).to eq(12)
    expect(component.fact({ "page" => 0 }, :page)).to eq(0)
    expect(component.fact({ active: false }, "active")).to be(false)
    expect(component.fact({}, :size)).to be_nil
  end
end
