# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Cron::ReapStalePaymentMethods do
  let_it_be(:customer) { create(:customer) }
  let(:user) { create(:user, customer: customer) }

  before { Current.customer = customer }

  def pm(psp_id:, status: "active", created_at: Time.current)
    create(:payment_method, customer: customer, user: user, provider: "stripe",
           psp_customer_id: "cus_x", psp_payment_method_id: psp_id,
           status: status, created_at: created_at)
  end

  it "soft-removes a stale pending vault placeholder" do
    stale = pm(psp_id: "pending:old", created_at: 2.days.ago)
    described_class.perform
    expect(stale.reload.status).to eq("removed")
  end

  it "leaves a recent pending placeholder alone" do
    recent = pm(psp_id: "pending:new", created_at: 1.hour.ago)
    described_class.perform
    expect(recent.reload.status).to eq("active")
  end

  it "never touches a confirmed card, however old" do
    confirmed = pm(psp_id: "pm_real", created_at: 10.days.ago)
    described_class.perform
    expect(confirmed.reload.status).to eq("active")
  end
end
