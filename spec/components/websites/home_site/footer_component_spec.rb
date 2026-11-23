# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::HomeSite::FooterComponent, type: :component do
  it "renders saved columns, future-scoped desktop wording and safe locale-preserving links" do
    site = Website.new(customer_id: 81_721_200, name: '<b>Brand</b>', tagline: 'Editable tagline', footer: {
      blurb: 'Saved blurb', columns: [{ heading: 'Desktop', links: [
        { label: 'Windows app — Coming soon', url: 'platform' }, { label: 'Unsafe', url: 'javascript:alert(1)' }
      ] }]
    })
    I18n.with_locale(:'zh-CN') do
      html = render_inline(described_class.new(website: site, theme: website_theme))
      expect(html.css('a').map { |node| [node.text.strip, node['href']] }).to eq([['Windows app — Coming soon', '/platform?locale=zh-CN']])
      expect(html).to have_text('Saved blurb')
      expect(html).to have_text("© #{Time.current.year} <b>Brand</b>")
      expect(html).to have_text('Editable tagline')
      expect(html.css('b')).to be_empty
      expect(html.at_css('a')['class']).to include('min-h-11', 'min-w-11', 'text-[15px]', 'focus-visible:ring-2')
      expect(html.css('p').first['class']).to include('text-[22px]', 'text-white')
      expect(html.css('p').find { |node| node.text == 'Saved blurb' }['class']).to include('text-[15px]', 'text-slate-400')
      expect(html.css('[class]').any? { |node| node['class'].include?('grid-cols-1') && node['class'].include?('min-[380px]:grid-cols-3') }).to be(true)
      expect(html.at_css('footer')['class']).to include('bg-slate-950', 'isolate', 'overflow-hidden')
      expect(html.at_css('footer > div:not([aria-hidden])')['class']).to include('max-w-[1280px]')
      wordmark = html.css('div[aria-hidden="true"]').find { |node| node['class'].to_s.include?('bg-clip-text') }
      expect(wordmark.text).to eq('<b>Brand</b>')
      expect(html.at_css('a')['class']).to include('text-slate-300', 'hover:text-white', 'focus-visible:ring-violet-400', 'focus-visible:ring-offset-slate-950')
      mark = html.at_css('svg')
      expect(mark['aria-hidden']).to eq('true')
      expect(mark['focusable']).to eq('false')
      expect(mark['viewBox']).to eq('-99.28 24.33 695.48 575.82')
      expect(mark.to_html).to include('#7f22fe')
      expect(html.css('h1, img, button')).to be_empty
    end
  end

  it "omits empty or unsafe edited columns without inventing destinations" do
    site = Website.new(customer_id: 81_721_200, name: 'Saved brand', footer: { columns: [
      nil, {}, { links: [{ label: 'Invalid', url: 'javascript:alert(1)' }] },
      { heading: 'Saved heading', links: [{ label: ' ', url: 'pricing' }] }
    ] })
    html = render_inline(described_class.new(website: site, theme: website_theme))
    expect(html.css('a')).to be_empty
    expect(html.css('p').map { |node| node.text.strip }).to eq(['Saved brand', 'Saved heading'])
    expect(html).not_to have_text('Invalid')
  end
end
