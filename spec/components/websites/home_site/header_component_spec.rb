# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::HomeSite::HeaderComponent, type: :component do
  it "uses saved order, filters unavailable pages, and exposes current navigation, skip link and both signup placements" do
    site = Website.new(id: 7, customer_id: 81_721_200, name: 'Owner <b>brand</b>')
    pages = %w[pricing platform contact].map { |slug| WebsitePage.new(website_id: 7, customer_id: 81_721_200, title: slug, slug: slug, published: true, nav_visible: true) }
    pages.last.published = false
    foreign = pages.first.dup.tap { |record| record.website_id = 8 }
    other_tenant = pages.first.dup.tap { |record| record.customer_id = 81_721_201 }
    hidden = pages.first.dup.tap { |record| record.nav_visible = false }
    I18n.with_locale(:'zh-CN') do
      html = render_inline(described_class.new(website: site, pages: [*pages, foreign, other_tenant, hidden], current_slug: 'pricing', theme: website_theme))
      expect(html.css('header nav a').map(&:text)).to eq(%w[pricing platform])
      expect(html).to have_css('header nav a[aria-current="page"]', text: 'pricing')
      expect(html).to have_css('a[href="#site-main"]', text: I18n.t('chrome.skip_to_content'))
      expect(html.css('a[href="/auth/sign_up?locale=zh-CN"]').size).to eq(2)
      expect(html.at_css('header a[href="/auth/sign_up?locale=zh-CN"]').parent['class']).to eq('hidden lg:flex')
      expect(html).to have_css('[data-controller="website-nav"] [data-website-nav-target="trigger"][aria-expanded="false"]')
      expect(html.at_css('#website-nav-panel').ancestors.map(&:name)).not_to include('header')
      expect(html.css('b')).to be_empty
      expect(html.css('header summary').first['class']).to include('min-h-11')
      expect(html.css('header nav a').map { |node| node['class'] }).to all(include('text-[14px]'))
      expect(html.css('header summary').first['class']).to include('text-[14px]')
      expect(html.css('[role="menuitem"]').map { |node| node['lang'] }).to eq(%w[en zh-CN])
      expect(html).to have_css('dialog#website-nav-panel')
      expect(html.at_css('header')['class']).to include('bg-slate-950/75', 'backdrop-blur-xl', 'border-b', 'border-white/10')
      expect(html.at_css('header > div')['class']).to include('max-w-[1280px]')
      expect(html.at_css('header nav a[aria-current="page"]')['class']).to include('bg-white/15', 'text-white')
      expect(html.at_css('header a[href="/auth/sign_up?locale=zh-CN"]')['class']).to include('rounded-full', 'from-violet-600')
      expect(html.css('header > div > a > span').map(&:text)).to eq([site.name])
      mark = html.at_css('header > div > a svg')
      expect(mark['aria-hidden']).to eq('true')
      expect(mark['focusable']).to eq('false')
      expect(mark['viewBox']).to eq('-99.28 24.33 695.48 575.82')
      expect(mark.to_html).to include('#7f22fe')
      expect(html.css('h1, img')).to be_empty
    end
  end

  it 'gives the brand its own row below 280 CSS pixels and lets controls wrap without fixed narrow height' do
    site = Website.new(id: 7, customer_id: 81_721_200, name: 'AnysysCompleteOwnerWordmark')
    html = render_inline(described_class.new(website: site, theme: website_theme))
    bar = html.at_css('header > div')
    brand = bar.at_css('a')
    controls = bar.at_css('button').parent
    expect(bar['class'].split).to include('h-auto', 'flex-col', 'min-[280px]:flex-row', 'min-[280px]:min-h-16', '[overflow-wrap:anywhere]')
    expect(brand.text).to eq(site.name)
    expect(brand['class'].split).to include('min-w-0', 'w-full', 'text-[20px]', 'min-[280px]:w-auto')
    expect(controls['class'].split).to include('min-w-0', 'w-full', 'flex-wrap')
    expect(brand['class']).not_to include('truncate', 'overflow-hidden')
    panel = html.at_css('[role="menu"]')
    expect(panel['class']).to include('w-[min(11rem,calc(100vw-2.5rem))]')
    expect(html.css('[role="menuitem"]').map { |node| node['class'] }).to all(include('text-[14px]'))
  end
end
