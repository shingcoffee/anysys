# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::HomeSite::MobileNavSheetComponent, type: :component do
  it "uses a native modal with self-only backdrop dismissal and adds signup exactly once" do
    site = Website.new(id: 7, customer_id: 81_721_200, name: 'Brand')
    html = render_inline(described_class.new(website: site, theme: website_theme, open_label: 'Open', close_label: 'Close'))
    expect(html).to have_no_css('[data-website-nav-target="backdrop"]', visible: :all)
    expect(html).to have_css('dialog#website-nav-panel[data-website-nav-target="panel"][aria-modal="true"][aria-labelledby="website-nav-title"]', visible: :all)
    expect(html.at_css('dialog')['data-action']).to eq('cancel->website-nav#close:prevent click->website-nav#dismissBackdrop')
    expect(html.at_css('dialog')['class']).to include('m-0', 'h-dvh', 'max-h-none', 'max-w-none', 'bg-transparent', 'backdrop:bg-black/40')
    expect(html.at_css('dialog')['open']).to be_nil
    expect(html).to have_css('dialog > div.ml-auto.h-full.bg-white', visible: :all)
    expect(html).to have_css('button[data-action="click->website-nav#close"][aria-label="Close"][autofocus]', visible: :all)
    expect(html.css('a[href="/auth/sign_up"]').size).to eq(1)
    expect(html.at_css('button')['class']).to include('size-11', 'focus-visible:ring-2')
  end
end
