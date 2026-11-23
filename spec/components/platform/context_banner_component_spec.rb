# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Platform::ContextBannerComponent, type: :component do
  include Rails.application.routes.url_helpers

  let(:platform_customer) { create(:customer, id: 81_721_200, name: 'Platform Owner') }
  let(:target_customer)   { create(:customer, name: 'Acme Industries') }

  after { Current.reset }

  describe '#render?' do
    it 'returns true when platform_owner_context is true' do
      Current.platform_owner_context = true
      Current.acting_as_customer = target_customer
      expect(described_class.new.render?).to be true
    end

    it 'returns false when platform_owner_context is false or nil' do
      aggregate_failures do
        Current.platform_owner_context = false
        expect(described_class.new.render?).to be false

        Current.platform_owner_context = nil
        expect(described_class.new.render?).to be false
      end
    end
  end

  context 'when rendered in platform owner context' do
    before do
      Current.platform_owner_context = true
      Current.acting_as_customer     = target_customer
      Current.original_customer      = platform_customer
      render_inline(described_class.new)
    end

    it 'displays platform admin mode text, target customer name and ID, return link, amber background, and sticky position' do
      aggregate_failures do
        expect(page).to have_text('Platform Admin Mode')
        expect(page).to have_text('Acme Industries')
        expect(page).to have_text(target_customer.id.to_s)
        expect(page).to have_link('Return to Platform',
          href: admin_maintenance_platform_customer_context_path(Authentication::User::PLATFORM_CUSTOMER_ID))
        expect(page).to have_css('.bg-amber-500')
        expect(page).to have_css('.sticky.top-0')
      end
    end
  end

  context 'when not in platform owner context' do
    before { Current.platform_owner_context = false }

    it 'does not render anything' do
      render_inline(described_class.new)
      expect(page.native.inner_html).to be_empty
    end
  end
end
