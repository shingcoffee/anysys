# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::Website::Provisioner do
  let_it_be(:customer) { create(:customer) }

  before { Current.customer = customer }
  after  { Current.customer = nil }

  describe ".call" do
    it "provisions a website and is idempotent" do
      site = described_class.call(customer)
      expect(site).to be_a(Website)
      expect(site.pages).to be_present

      expect { described_class.call(customer) }.not_to change(Website, :count)
    end
  end

  describe ".deprovision" do
    it "unpublishes the website and keeps the rows" do
      site = described_class.call(customer)
      site.update!(published: true)
      site.pages.update_all(published: true)

      expect { described_class.deprovision(customer) }.not_to change(Website, :count)
      expect(site.reload.published).to be(false)
      expect(WebsitePage.where(website_id: site.id)).to be_present
    end

    it "is a no-op when the customer has no website" do
      expect { described_class.deprovision(customer) }.not_to raise_error
    end
  end
end
