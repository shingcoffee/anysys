require "rails_helper"

RSpec.describe Authentication::Settings do
  let_it_be(:customer) { create(:customer) }

  # `status` is positional (not a keyword) so bare-hash calls like
  # `assign("allow_registration" => true)` parse the hash as `config_hash`.
  def assign(config_hash, status = :active)
    fm = FeatureModules::Module.find_by!(key: "authentication")
    cfm = FeatureModules::CustomerAssignment.find_by!(
      customer_id: customer.id, feature_module_id: fm.id
    )
    cfm.update!(status: status, configuration: config_hash.to_json)
  end

  describe "#signup_enabled?" do
    it "is false when allow_registration is missing (schema default)" do
      assign({})
      expect(described_class.for(customer.id).signup_enabled?).to eq(false)
    end

    it "is true when allow_registration is true" do
      assign("allow_registration" => true)
      expect(described_class.for(customer.id).signup_enabled?).to eq(true)
    end

    it "is false when the auth module is suspended" do
      assign({ "allow_registration" => true }, :suspended)
      expect(described_class.for(customer.id).signup_enabled?).to eq(false)
    end

    it "is false when customer_id is blank" do
      expect(described_class.for(nil).signup_enabled?).to eq(false)
    end
  end

  describe "#password_reset_enabled?" do
    it "is true when allow_password_reset is missing (schema default true)" do
      assign({})
      expect(described_class.for(customer.id).password_reset_enabled?).to eq(true)
    end

    it "is false when allow_password_reset is explicitly false" do
      assign("allow_password_reset" => false)
      expect(described_class.for(customer.id).password_reset_enabled?).to eq(false)
    end
  end

  describe "#mfa_enabled?" do
    it "reads mfa_enabled from configuration" do
      assign("mfa_enabled" => true)
      expect(described_class.for(customer.id).mfa_enabled?).to eq(true)
    end

    it "treats a checkbox-style '1' as enabled" do
      assign("mfa_enabled" => "1")
      expect(described_class.for(customer.id).mfa_enabled?).to eq(true)
    end
  end

  describe "effective session and lockout policy" do
    it "reads integer and form-string tenant values" do
      assign("session_timeout" => "12", "max_login_attempts" => 3)
      settings = described_class.for(customer.id)

      expect(settings.timeout_in(default: 30.minutes)).to eq(12.minutes)
      expect(settings.maximum_attempts(default: 10)).to eq(3)
    end

    [nil, "", "invalid", "2.5", 2.5, 0, -1, false, [], {}].each do |value|
      it "retains class defaults for invalid policy value #{value.inspect}" do
        assign("session_timeout" => value, "max_login_attempts" => value)
        settings = described_class.for(customer.id)

        expect(settings.timeout_in(default: 45.minutes)).to eq(45.minutes)
        expect(settings.maximum_attempts(default: 7)).to eq(7)
      end
    end

    it "uses defaults when the assignment is inactive" do
      assign({ "session_timeout" => 1, "max_login_attempts" => 1 }, :suspended)
      settings = described_class.for(customer.id)

      expect(settings.timeout_in(default: 30.minutes)).to eq(30.minutes)
      expect(settings.maximum_attempts(default: 10)).to eq(10)
    end

    it "uses defaults without a customer or assignment" do
      settings = described_class.for(nil)

      expect(settings.timeout_in(default: 30.minutes)).to eq(30.minutes)
      expect(settings.maximum_attempts(default: 10)).to eq(10)
    end
  end
end
