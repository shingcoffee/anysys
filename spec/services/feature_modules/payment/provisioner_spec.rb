require "rails_helper"

RSpec.describe FeatureModules::Payment::Provisioner do
  let_it_be(:customer) { create(:customer) }

  before { Current.customer = customer }

  # Helper — mark a set of provider keys as platform-available.
  def make_available(*providers)
    providers.each { |p| Payments::PlatformGateway.for_provider(p).update!(available: true) }
  end

  # The tenant scope is bypassed here so the spec can assert on the customer's
  # seeded rows directly, regardless of Current.customer.
  def customer_accounts
    Payments::MerchantAccount.unscoped_by_tenant.where(customer_id: customer.id)
  end

  describe "seeding respects platform availability" do
    it "seeds accounts only for platform-available tenders" do
      make_available("alipay")
      # wechat_pay and stripe are left unavailable

      expect { described_class.call(customer) }
        .to change { customer_accounts.count }
        .by(2) # alipay x (sandbox + production)

      expect(customer_accounts.distinct.pluck(:provider)).to contain_exactly("alipay")
    end

    it "seeds nothing when no tenders are available" do
      # All providers default to unavailable
      expect { described_class.call(customer) }.not_to change { customer_accounts.count }
    end

    it "seeds all registered tenders when all are available" do
      Payments::Gateways.keys.each { |k| make_available(k.to_s) }

      expected_matrix = Payments::Gateways.keys.map(&:to_s).product(%w[sandbox production])

      expect { described_class.call(customer) }
        .to change { customer_accounts.count }
        .by(expected_matrix.size)

      expect(customer_accounts.pluck(:provider, :mode)).to match_array(expected_matrix)
      expect(customer_accounts.pluck(:status).uniq).to eq(["disabled"])
    end
  end

  describe "idempotency" do
    it "does not duplicate accounts on repeated calls" do
      make_available("alipay")
      described_class.call(customer)
      expect { described_class.call(customer) }.not_to change { customer_accounts.count }
    end
  end

  describe ".revoke" do
    it "disables all accounts without destroying them (preserves credentials)" do
      make_available("alipay")
      described_class.call(customer)
      acc = customer_accounts.first
      acc.update!(status: "active", merchant_id: "real-mch", credentials_json: { "app_id" => "secret" })

      expect { described_class.revoke(customer) }.not_to change { customer_accounts.count }

      expect(customer_accounts.pluck(:status).uniq).to eq(["disabled"])
      # Credentials + real merchant id survive the toggle-off.
      acc.reload
      expect(acc.merchant_id).to eq("real-mch")
      expect(acc.credential(:app_id)).to eq("secret")
    end
  end
end
