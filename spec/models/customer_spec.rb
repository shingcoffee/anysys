# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Customer, type: :model do
  let(:valid_attributes) do
    {
      name: 'Test Customer',
      alias: 'TC',
      address: '123 Main St',
      contact: 'John Doe',
      phone: '555-1234',
      tier: :basic,
      industry: :technology
    }
  end

  # overrides is positional (not keyword) so bare-hash calls like build_customer(name: '')
  # bind the whole hash rather than being swallowed as keywords.
  def build_customer(overrides = {})
    described_class.new(valid_attributes.merge(overrides))
  end

  def create_customer(overrides = {})
    described_class.create!(valid_attributes.merge(overrides))
  end

  describe 'domain' do
    before { allow(CustomDomains::CnameVerifier).to receive(:call).and_return(:verified) }

    it 'stores a normalized domain' do
      customer = create_customer(domain: 'Forms.Example.COM.')
      expect(customer.reload.domain).to eq('forms.example.com')
    end

    it 'clears a blank domain' do
      customer = create_customer(domain: 'forms.example.com')
      expect(CustomDomains::CnameVerifier).not_to receive(:call)
      customer.update!(domain: '  ')
      expect(customer.domain).to be_nil
    end

    it 'rejects an invalid domain and keeps the typed value' do
      customer = build_customer(domain: 'https://forms.example.com/path')
      expect(customer).not_to be_valid
      expect(customer.errors[:domain]).to include(I18n.t('custom_domains.errors.invalid_domain'))
      expect(customer.domain).to eq('https://forms.example.com/path')
    end

    it 'rejects a domain owned by another customer' do
      create_customer(domain: 'forms.example.com')
      other = build_customer(name: 'Other', domain: 'FORMS.example.com')
      expect(other).not_to be_valid
      expect(other.errors[:domain]).to include(I18n.t('custom_domains.errors.domain_taken'))
    end

    it 'rejects an unverified CNAME when the domain changes' do
      allow(CustomDomains::CnameVerifier).to receive(:call).with(hostname: 'forms.example.com').and_return(:unverified)
      customer = build_customer(domain: 'forms.example.com')
      expect(customer).not_to be_valid
      expect(customer.errors[:domain]).to include(I18n.t('custom_domains.errors.cname_unverified'))
    end

    it 'does not check DNS when the saved domain is unchanged' do
      customer = create_customer(domain: 'forms.example.com')
      expect(CustomDomains::CnameVerifier).not_to receive(:call)
      customer.update!(name: 'Renamed', domain: 'forms.example.com')
      expect(customer.name).to eq('Renamed')
    end
  end

  describe 'validations' do
    %i[status tier role industry].each do |attribute|
      it "validates an unknown #{attribute} without raising during assignment" do
        customer = build_customer(attribute => "not_a_supported_value")
        expect(customer).not_to be_valid
        expect(customer.errors[attribute]).to be_present
      end
    end

    it 'is valid with valid attributes' do
      expect(build_customer).to be_valid
    end

    it 'requires a name' do
      customer = build_customer(name: '')
      expect(customer).not_to be_valid
      expect(customer.errors[:name]).to include("can't be blank")
    end

    it 'requires name to be at most 100 characters' do
      customer = build_customer(name: 'a' * 101)
      expect(customer).not_to be_valid
      expect(customer.errors[:name]).to include('is too long (maximum is 100 characters)')
    end

    it 'requires an industry' do
      customer = build_customer(industry: nil)
      expect(customer).not_to be_valid
      expect(customer.errors[:industry]).to include("can't be blank")
    end

    it 'allows optional fields to be blank' do
      customer = described_class.new(name: 'Minimal Customer', industry: :technology)
      expect(customer).to be_valid
    end

    describe 'locale' do
      it 'is valid with a supported locale' do
        expect(build_customer(locale: 'zh-CN')).to be_valid
      end

      it 'is valid when blank (no tenant override)' do
        expect(build_customer(locale: '')).to be_valid
      end

      it 'rejects an unsupported locale' do
        customer = build_customer(locale: 'fr')
        expect(customer).not_to be_valid
        expect(customer.errors[:locale]).to include('is not included in the list')
      end

      it 'normalizes a blank locale to nil' do
        expect(create_customer(locale: '').locale).to be_nil
      end
    end
  end

  describe 'enums' do
    describe 'tier' do
      it 'defaults to basic' do
        customer = described_class.new(name: 'Test')
        expect(customer.tier).to eq('basic')
      end

      it 'accepts all tier values' do
        %i[basic standard premium enterprise].each do |tier|
          customer = build_customer(tier: tier)
          expect(customer.tier).to eq(tier.to_s)
        end
      end
    end

    describe 'status' do
      it 'defaults to active' do
        customer = described_class.new(name: 'Test')
        expect(customer.status).to eq('active')
      end

      it 'accepts active and inactive' do
        customer = build_customer
        expect(customer).to be_active

        customer.status = :inactive
        expect(customer).to be_inactive
      end
    end

    describe 'role' do
      it 'defaults to owner' do
        customer = described_class.new(name: 'Test')
        expect(customer.role).to eq('owner')
      end

      it 'accepts all role values' do
        %i[owner admin member].each do |role|
          customer = build_customer(role: role)
          expect(customer.role).to eq(role.to_s)
        end
      end

      it 'provides predicate methods' do
        customer = build_customer(role: :admin)
        expect(customer).to be_admin
        expect(customer).not_to be_owner
        expect(customer).not_to be_member
      end
    end

    describe 'industry' do
      it 'defaults to nil (but is required for validity)' do
        customer = described_class.new(name: 'Test')
        expect(customer.industry).to be_nil
        expect(customer).not_to be_valid
      end

      it 'accepts industry values' do
        %i[technology healthcare retail consulting].each do |industry|
          customer = build_customer(industry: industry)
          expect(customer.industry).to eq(industry.to_s)
        end
      end

      it 'provides predicate methods' do
        customer = build_customer(industry: :technology)
        expect(customer).to be_technology
      end

      it 'covers all major industry sectors' do
        industries = described_class.industries.keys
        expect(industries).to include(
          # Technology & Digital
          'technology', 'software', 'telecommunications', 'cybersecurity',
          'blockchain_cryptocurrency', 'internet_of_things', 'data_analytics',
          # Finance & Insurance
          'banking', 'insurance', 'fintech', 'investment_management',
          # Healthcare & Life Sciences
          'healthcare', 'pharmaceuticals', 'biotechnology', 'dental', 'veterinary',
          # Education & Research
          'education', 'higher_education', 'edtech', 'research',
          # Manufacturing & Industrial
          'manufacturing', 'automotive', 'aerospace', 'electronics',
          'food_processing', 'textiles_apparel', 'metals_steel', 'robotics_automation',
          # Primary Industries
          'agriculture', 'forestry_timber', 'fishing_aquaculture',
          # Retail & Consumer
          'retail', 'ecommerce', 'fashion_apparel', 'jewelry_watches',
          # Food & Beverage
          'food_beverage', 'restaurants',
          # Energy & Utilities
          'energy', 'oil_gas', 'renewable_energy', 'mining',
          # Construction & Real Estate
          'construction', 'real_estate', 'architecture', 'interior_design', 'engineering_services',
          # Transportation & Logistics
          'transportation', 'logistics', 'airlines', 'maritime', 'railroad',
          'warehousing_storage', 'courier_postal',
          # Media & Entertainment
          'media', 'entertainment', 'publishing', 'film_television', 'photography_videography',
          # Professional Services
          'consulting', 'legal', 'recruitment', 'marketing', 'translation_interpretation',
          # Hospitality & Tourism
          'hospitality', 'travel_tourism', 'event_management',
          # Government & Public Sector
          'government', 'defense', 'space_technology',
          # Nonprofit & Social
          'nonprofit', 'social_services', 'religious_organizations',
          # Trades & Maintenance
          'hvac_plumbing_electrical', 'automotive_repair', 'cleaning_janitorial',
          'landscaping_lawn_care', 'pest_control',
          # Other
          'waste_management_recycling', 'security_services', 'funeral_memorial',
          'dry_cleaning_laundry', 'cannabis', 'coworking_shared_spaces', 'other'
        )
      end

      it 'has all enum keys present in INDUSTRY_GROUPS' do
        grouped_keys = Customer::INDUSTRY_GROUPS.values.flatten
        enum_keys = described_class.industries.keys.map(&:to_sym)
        expect(grouped_keys).to match_array(enum_keys)
      end

      it "translates every industry key in en and zh-CN" do
        described_class.industries.keys.each do |key|
          expect(I18n.t("customers.industries.#{key}", locale: :en, raise: true)).to eq(key.to_s.titleize)
          zh = I18n.t("customers.industries.#{key}", locale: :"zh-CN", raise: true)
          expect(zh).to be_present
          expect(zh).not_to eq(key.to_s.titleize)
        end
      end
    end
  end

  describe "#industry_label" do
    it "returns the locale industry name" do
      customer = build_customer(industry: :technology)
      expect(customer.industry_label).to eq("Technology")
      I18n.with_locale(:"zh-CN") { expect(customer.industry_label).to eq("科技") }
    end

    it "returns nil when industry is blank" do
      customer = described_class.new
      expect(customer.industry_label).to be_nil
    end
  end

  describe ".industry_label_for" do
    it "looks up a key without a Customer instance" do
      expect(described_class.industry_label_for("healthcare")).to eq("Healthcare")
      I18n.with_locale(:"zh-CN") do
        expect(described_class.industry_label_for("healthcare")).to eq("医疗健康")
      end
    end

    it "returns nil for a blank key" do
      expect(described_class.industry_label_for(nil)).to be_nil
      expect(described_class.industry_label_for("")).to be_nil
    end
  end

  describe ".grouped_industry_options" do
    it "uses locale industry labels for option text" do
      tech = described_class.grouped_industry_options.find { |g, _| g == "Technology & Digital" }
      expect(tech.last).to include(["Technology", "technology"])
      I18n.with_locale(:"zh-CN") do
        tech_zh = described_class.grouped_industry_options.find { |g, _| g == "科技与数字" }
        expect(tech_zh.last).to include(["科技", "technology"])
      end
    end
  end

  describe ".industry_group_label" do
    it "translates every INDUSTRY_GROUPS name in en and zh-CN" do
      described_class::INDUSTRY_GROUPS.keys.each do |name|
        expect(described_class.industry_group_label(name)).to eq(name)
        zh = I18n.t(
          "customers.industry_groups.#{name.parameterize(separator: "_")}",
          locale: :"zh-CN", raise: true
        )
        expect(zh).to be_present
        expect(zh).not_to eq(name) unless name == "Other"
      end
    end

    it "localizes Technology & Digital in zh-CN" do
      I18n.with_locale(:"zh-CN") do
        expect(described_class.industry_group_label("Technology & Digital")).to eq("科技与数字")
      end
    end

    it "returns nil for a blank name" do
      expect(described_class.industry_group_label(nil)).to be_nil
      expect(described_class.industry_group_label("")).to be_nil
    end
  end

  describe 'random ID generation' do
    it 'generates an 8-digit ID' do
      customer = create_customer
      expect(customer.id.to_s.length).to eq(8)
    end

    it 'generates IDs in the correct range' do
      customer = create_customer
      expect(customer.id).to be >= 10_000_000
      expect(customer.id).to be <= 99_999_999
    end

    it 'generates unique IDs' do
      ids = 5.times.map do |i|
        create_customer(name: "Customer #{i}").id
      end
      expect(ids.uniq.length).to eq(5)
    end
  end

  describe 'scopes' do
    before do
      create_customer(name: 'Zebra Corp', tier: :enterprise)
      create_customer(name: 'Alpha Inc', tier: :basic)
      create_customer(name: 'Beta Ltd', tier: :premium)
    end

    describe '.by_name' do
      it 'orders customers alphabetically by name' do
        customers = described_class.by_name
        expect(customers.first.name).to eq('Alpha Inc')
        expect(customers.last.name).to eq('Zebra Corp')
      end
    end

    describe '.recent' do
      it 'orders customers by creation date descending' do
        customers = described_class.recent
        expect(customers.first.name).to eq('Beta Ltd')
      end
    end

    describe '.search' do
      let!(:acme) { create_customer(name: 'Acme Corp', alias: 'AC') }
      let!(:other) { create_customer(name: 'Other Inc', alias: 'globex') }

      it 'returns all customers when query is blank' do
        expect(described_class.search('').count).to eq(described_class.count)
      end

      it 'returns all customers when query is whitespace only' do
        expect(described_class.search("   \t  ").count).to eq(described_class.count)
      end

      it 'finds customers by name token (case-insensitive)' do
        names = described_class.search('ZEBRA').pluck(:name)
        expect(names).to contain_exactly('Zebra Corp')
      end

      it 'finds customers by alias token' do
        names = described_class.search('globex').pluck(:name)
        expect(names).to contain_exactly('Other Inc')
      end

      it 'finds a customer by exact id when token is all digits' do
        names = described_class.search(acme.id.to_s).pluck(:name)
        expect(names).to include('Acme Corp')
      end

      it 'all-digits token also matches name/alias substrings containing those digits' do
        digit = create_customer(name: 'Route66', alias: 'r66')
        names = described_class.search('66').pluck(:name)
        expect(names).to include('Route66')
      end

      it 'mixed alphanumeric token does not match by id' do
        names = described_class.search('xyz123').pluck(:name)
        expect(names).to be_empty
      end

      it 'multi-token AND across name and alias' do
        create_customer(name: 'Acme Foo', alias: 'BAR')
        names = described_class.search('acme bar').pluck(:name)
        expect(names).to contain_exactly('Acme Foo')
      end

      it 'multi-token AND with no row matching every token returns empty' do
        names = described_class.search('alpha zebra').pluck(:name)
        expect(names).to be_empty
      end

      it 'treats LIKE wildcards in user input as literal characters' do
        create_customer(name: '100% Success', alias: 'AC')
        create_customer(name: '100 Wins', alias: 'AC')
        names = described_class.search('100%').pluck(:name)
        expect(names).to contain_exactly('100% Success')
      end
    end
  end

  describe 'soft delete' do
    let(:customer) { create_customer }

    it 'can be soft deleted' do
      customer.soft_delete
      expect(customer.status).to eq('inactive')
    end

    it 'is not visible after soft delete' do
      customer.soft_delete
      expect(described_class.visible).not_to include(customer)
    end

    it 'can be restored' do
      customer.soft_delete
      customer.restore
      expect(customer.status).to eq('active')
      expect(described_class.visible).to include(customer)
    end

    it 'appears in only_deleted scope after soft delete' do
      customer.soft_delete
      expect(described_class.only_deleted).to include(customer)
    end
  end

  describe "after_create reserved roles" do
    it "seeds owner, admin, member" do
      customer = create(:customer)
      expect(customer.roles.pluck(:key).sort).to eq(%w[admin member owner])
    end
  end

  describe "after_create billing onboarding" do
    before do
      # Ensure settings singleton and a seeded default plan are available
      Billing::Settings.current
      Billing::PlanLimit.delete_all
      Billing::Plan.delete_all
      Billing::CountableItem.delete_all
      Billing::StandardPlans.seed!

      # Silence mailer deliveries so invoice finalization doesn't raise
      allow(BillingMailer).to receive_message_chain(:with, :invoice_issued, :deliver_later)
    end

    it "creates a live subscription to the default plan when a customer is created" do
      customer = create(:customer)

      subs = Billing::Subscription.unscoped_by_tenant
                                  .where(customer_id: customer.id)
                                  .live
      expect(subs.count).to eq(1)
      expect(subs.first.billing_plan_id).to eq(Billing::Plan.default_plan.id)
    end

    it "is idempotent — a second Billing::Onboarding.call does not create a duplicate subscription" do
      customer = create(:customer)

      expect {
        Billing::Onboarding.call(customer)
      }.not_to change {
        Billing::Subscription.unscoped_by_tenant.where(customer_id: customer.id).live.count
      }
    end

    context "when no default plan exists" do
      before { Billing::Plan.update_all(is_default: false) }

      it "creates the customer without raising and without a subscription" do
        customer = nil
        expect { customer = create(:customer) }.not_to raise_error
        subs = Billing::Subscription.unscoped_by_tenant.where(customer_id: customer.id)
        expect(subs.count).to eq(0)
      end
    end
  end
end
