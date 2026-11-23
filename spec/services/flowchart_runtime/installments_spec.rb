# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Installments do
  let(:ctx) { { errors: [] } }

  def build(**overrides)
    described_class.build(ctx, principal: 10_000, **overrides)
  end

  it "computes a 12-month 12% annuity payment of 888.49" do
    travel_to Time.zone.local(2026, 1, 15, 12) do
      plan = build(annual_rate: 12, periods: 12, frequency: "monthly", method: "annuity")
      schedule = plan["schedule"]
      expect(schedule.size).to eq(12)
      expect(schedule.first["payment"]).to eq("888.49")
      expect(schedule.first["due_date"]).to eq("2026-02-15")
      expect(schedule.last["balance"]).to eq("0.00")
      principal = schedule.sum { |row| BigDecimal(row["principal"]) }
      expect(principal).to eq(BigDecimal("10000.00"))
      expect { JSON.generate(plan) }.not_to raise_error
    end
  end

  it "declines interest on equal principal and balloons interest-only" do
    equal = build(annual_rate: 12, periods: 12, method: "equal_principal")
    expect(equal["schedule"].first["principal"]).to eq(equal["schedule"][1]["principal"])
    expect(BigDecimal(equal["schedule"].first["interest"])).to be > BigDecimal(equal["schedule"].last["interest"])

    interest_only = build(annual_rate: 12, periods: 12, method: "interest_only")
    expect(interest_only["schedule"][0..10].map { |row| row["principal"] }.uniq).to eq(["0.00"])
    expect(interest_only["schedule"].last["principal"]).to eq("10000.00")
  end

  it "charges flat interest on the original principal" do
    plan = build(annual_rate: 12, periods: 12, method: "flat")
    expect(plan["totals"]["interest"]).to eq("1200.00")
    expect(plan["totals"]["principal"]).to eq("10000.00")
    expect(plan["schedule"].first["interest"]).to eq("100.00")
  end

  it "fails when the down payment consumes the principal" do
    expect(build(down_payment: 10_000)).to be(false)
    expect(ctx[:error_details].last["code"]).to eq("build_installment_plan.down_payment_exceeds_principal")
  end

  it "fails on a non-numeric principal" do
    expect(described_class.build(ctx, principal: "abc")).to be(false)
    expect(ctx[:error_details].last["code"]).to eq("build_installment_plan.invalid_principal")
  end

  it "fails instead of clamping a period count outside 1..600" do
    [0, 601, "twelve"].each do |periods|
      ctx[:error_details] = []
      expect(build(periods: periods)).to be(false), periods.inspect
      expect(ctx[:error_details].last["code"]).to eq("build_installment_plan.invalid_periods")
    end
    expect(ctx[:errors].last).to eq(I18n.t("flowchart_runtime.errors.build_installment_plan.invalid_periods", max: 600))
  end

  it "fails on an unparseable start date but treats a blank one as today" do
    expect(build(start_date: "2026-13-45")).to be(false)
    expect(ctx[:error_details].last["code"]).to eq("build_installment_plan.invalid_start_date")

    travel_to Time.zone.local(2026, 3, 10, 12) do
      expect(build(start_date: "")["schedule"].first["due_date"]).to eq("2026-04-10")
    end
  end
end
