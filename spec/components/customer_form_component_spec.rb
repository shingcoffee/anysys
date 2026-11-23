# frozen_string_literal: true

require "rails_helper"

RSpec.describe CustomerFormComponent, type: :component do
  let(:tenant_customer)   { Customer.create!(name: "Tenant Customer", role: :owner, industry: :technology) }
  let(:new_customer)      { Customer.new }
  let(:existing_customer) { Customer.create!(name: "Test Customer", tier: :premium, industry: :healthcare) }

  describe "#initialize" do
    it "accepts a customer" do
      expect(described_class.new(customer: new_customer).customer).to eq(new_customer)
    end

    it "accepts a customer_id" do
      expect(described_class.new(customer: new_customer, customer_id: tenant_customer.id).current_customer_id)
        .to eq(tenant_customer.id)
    end
  end

  describe "#form_method" do
    it "returns :post for new customer" do
      expect(described_class.new(customer: new_customer).form_method).to eq(:post)
    end

    it "returns :patch for existing customer" do
      expect(described_class.new(customer: existing_customer).form_method).to eq(:patch)
    end
  end

  describe "#submit_label" do
    it "returns 'Create customer' for new customer" do
      expect(described_class.new(customer: new_customer).submit_label).to eq("Create customer")
    end

    it "returns 'Save changes' for existing customer" do
      expect(described_class.new(customer: existing_customer).submit_label).to eq("Save changes")
    end
  end

  describe "#tier_options" do
    it "returns all tier options" do
      options = described_class.new(customer: new_customer).tier_options
      aggregate_failures do
        expect(options).to include(["Basic", "basic"])
        expect(options).to include(["Standard", "standard"])
        expect(options).to include(["Premium", "premium"])
        expect(options).to include(["Enterprise", "enterprise"])
      end
    end
  end

  describe "#locale_options" do
    it "returns each available locale by its endonym" do
      options = described_class.new(customer: new_customer).locale_options
      aggregate_failures do
        expect(options).to include(["English", "en"])
        expect(options).to include(["简体中文", "zh-CN"])
      end
    end
  end

  describe "#industry_options" do
    subject(:options) { described_class.new(customer: new_customer).industry_options }

    it "returns grouped industry options with expected top-level groups" do
      group_names = options.map(&:first)
      aggregate_failures do
        expect(group_names).to include("Technology & Digital")
        expect(group_names).to include("Finance & Insurance")
        expect(group_names).to include("Healthcare & Life Sciences")
      end
    end

    it "includes specific industries within Technology & Digital group" do
      tech_group = options.find { |g| g.first == "Technology & Digital" }
      aggregate_failures do
        expect(tech_group.last).to include(["Technology", "technology"])
        expect(tech_group.last).to include(["Software", "software"])
      end
    end

    it "localizes industry option labels in zh-CN" do
      I18n.with_locale(:"zh-CN") do
        tech_group = options.find { |g| g.first == "科技与数字" }
        expect(tech_group.last).to include(["科技", "technology"])
      end
    end
  end

  describe "rendering" do
    context "new customer form" do
      before { render_inline(described_class.new(customer: new_customer, customer_id: tenant_customer.id)) }

      it "renders the form with all required fields" do
        aggregate_failures do
          expect(page).to have_css("form")
          expect(page).to have_css(".card", minimum: 3)
          expect(page).to have_css("h2", text: "Organization")
          expect(page).to have_css("h2", text: "Primary contact")
          expect(page).to have_css("h2", text: "Service plan")
          expect(page).to have_css("input#customer_name[required]")
          expect(page).to have_css("label.form-label-required", text: "Organization name")
          expect(page).to have_css("input#customer_domain")
          expect(page).to have_css("label", text: "Domain")
          expect(page).to have_css("input#customer_alias")
          expect(page).to have_css("textarea#customer_address")
          expect(page).to have_css("input#customer_contact")
          expect(page).to have_css("input#customer_phone")
          expect(page).to have_css("select#customer_tier")
          expect(page).to have_no_css("select#customer_role")
          expect(page).to have_no_text("Assigned when the account is created")
          expect(page).to have_css("select#customer_locale")
          expect(page).to have_css("select#customer_locale option[value='zh-CN']", visible: :all)
          expect(page).to have_css("select#customer_locale option[value='']", text: "Follow the browser", visible: :all)
          expect(page).to have_button("Create customer")
          expect(page).to have_link("Cancel")
        end
      end

      it "renders searchable industry select" do
        aggregate_failures do
          expect(page).to have_css("input#customer_industry[type='hidden']", visible: :all)
          expect(page).to have_css("[data-controller='searchable-select']")
          expect(page).to have_css("input[placeholder='Search industries...']")
        end
      end
    end

    context "existing customer form" do
      before { render_inline(described_class.new(customer: existing_customer, customer_id: tenant_customer.id)) }

      it "renders Update button and cancel link" do
        aggregate_failures do
          expect(page).to have_button("Save changes")
          expect(page).to have_text(existing_customer.id.to_s)
          expect(page).to have_text("Assigned when the account is created. It cannot be changed.")
          expect(page).to have_link("Cancel")
        end
      end
    end

    context "with validation errors" do
      let(:invalid_customer) { c = Customer.new; c.valid?; c }

      it "renders error messages" do
        render_inline(described_class.new(customer: invalid_customer, customer_id: tenant_customer.id))
        expect(page).to have_text("can't be blank")
      end
    end

    context "with existing customer data" do
      it "populates form fields with saved values" do
        customer = Customer.create!(
          name: "Filled Customer", alias: "FC",
          contact: "John Doe", phone: "555-1234",
          tier: :enterprise, industry: :technology, address: "123 Main St"
        )
        render_inline(described_class.new(customer: customer, customer_id: tenant_customer.id))

        aggregate_failures do
          expect(page).to have_css("input#customer_name[value='Filled Customer']")
          expect(page).to have_css("input#customer_alias[value='FC']")
          expect(page).to have_css("input#customer_domain", visible: :all)
        end
      end
    end
  end
end
