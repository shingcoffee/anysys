# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::PageFilters do
  describe ".paginate" do
    let_it_be(:customer) { create(:customer) }
    let(:user)     { create(:user, :member, customer: customer) }

    let!(:payments) do
      30.times.map do |i|
        order = create(:payment_order,
          customer:     customer,
          external_ref: "T-#{i}",
          subject:      "S",
          amount:       1.00 + (i / 100.0),
          currency:     "CNY",
          status:       "pending"
        )
        create(:payment,
          customer:     customer,
          user:         user,
          payment_order: order,
          provider:     "alipay",
          flow:         "qr",
          out_trade_no: "X-#{i}",
          amount:       1.00 + (i / 100.0),
          status:       "succeeded"
        )
      end
    end

    let(:scope) { Payments::Payment.where(user_id: user.id, customer_id: customer.id).order(:id) }

    it "returns the first page by default" do
      records, meta = described_class.paginate(scope, page: nil, per_page: 20)
      expect(records.size).to eq(20)
      expect(meta.page).to eq(1)
      expect(meta.limit).to eq(20)
      expect(meta.count).to eq(30)
    end

    it "returns the requested page" do
      records, meta = described_class.paginate(scope, page: 2, per_page: 20)
      expect(records.size).to eq(10)
      expect(meta.page).to eq(2)
    end

    it "clamps page to 1 when given garbage" do
      _records, meta = described_class.paginate(scope, page: "abc", per_page: 20)
      expect(meta.page).to eq(1)
    end

    it "clamps page to 1 when given a number less than 1" do
      _records, meta = described_class.paginate(scope, page: -3, per_page: 20)
      expect(meta.page).to eq(1)
    end

    it "does not 500 when page is an array" do
      records, meta = described_class.paginate(scope, page: ["2"], per_page: 20)
      expect(meta.page).to eq(1)
      expect(records.size).to eq(20)
    end

    it "exposes the page count" do
      _records, meta = described_class.paginate(scope, page: 1, per_page: 20)
      expect(meta.pages).to eq(2)
    end
  end
end
