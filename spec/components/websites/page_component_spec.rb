# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::PageComponent, type: :component do
  let(:theme) { website_theme }

  it "renders a known section headline and skips unknown or missing types" do
    site_page = website_page_record(sections: [
      { "id" => "1", "type" => "hero_split", "props" => { "headline" => "Infrastructure for ambitious teams." } },
      { "id" => "2", "type" => "not_a_kit", "props" => { "headline" => "Hidden" } },
      { "id" => "3", "type" => "hero_cinematic" },
      { "id" => "4" }
    ])

    html = render_inline(described_class.new(page: site_page, theme: theme, customer_id: 42))

    expect(html).to have_text("Infrastructure for ambitious teams.")
    expect(html.to_html).not_to include("Hidden")
    expect(html).to have_css("main [data-site-section='1']")
    expect(html).to have_css("main [data-site-section='3']")
  end

  it "wraps each section in its surface band and renders contrast sections with the inverted theme" do
    sections = [
      { "id" => "plain", "type" => "faq", "props" => { "heading" => "Plain" } },
      { "id" => "muted", "type" => "faq", "props" => { "heading" => "Muted", "surface" => "muted" } },
      { "id" => "flip", "type" => "faq", "props" => { "heading" => "Flip", "surface" => "contrast", "align" => "center" } },
      { "id" => "tint", "type" => "faq", "props" => { "heading" => "Tint", "surface" => "accent", "spacing" => "roomy" } }
    ]
    html = render_inline(described_class.new(sections: sections, theme: Websites::Theme.new("appearance" => "light", "accent" => "azure")))

    expect(html.at_css("[data-site-section='plain']")["data-section-surface"]).to be_nil
    expect(html.at_css("[data-site-section='muted'][data-section-surface='muted']")["class"]).to include("bg-neutral-50")
    flip = html.at_css("[data-site-section='flip'][data-section-surface='contrast']")
    expect(flip["class"]).to include("bg-neutral-950 text-white")
    expect(flip.to_html).to include("text-center")
    tint = html.at_css("[data-site-section='tint'][data-section-surface='accent']")
    expect(tint["class"]).to include("bg-sky-50/70")
    expect(tint.at_css("section")["class"]).to include("py-28 md:py-44")
  end

  it "renders an empty main when there are no sections" do
    site_page = website_page_record(sections: [])
    render_inline(described_class.new(page: site_page, theme: theme))

    expect(rendered_content).to include("min-h-[50vh]")
  end

  %i[en zh-CN].each do |locale|
    it "renders saved source order, multiline copy and exactly seven bundled photo placements in #{locale}" do
      definition = Websites::HomeSite.definition(locale: locale)
      site = Website.new(id: 7, customer_id: 81_721_200)
      expected_art = [
        %w[desktop-night studio-owner], %w[desktop-night team-collab], [], %w[about-team craft], %w[contact]
      ].map { |names| names.map { |name| "anysys-photo-#{name}.webp" } }
      rendered_sources = []

      I18n.with_locale(locale) do
        definition.fetch("pages").each_with_index do |source_page, index|
          aggregate_failures(source_page.fetch("title")) do
            attrs = source_page.slice('title', 'slug', 'home', 'sections')
            site_page = WebsitePage.new(**attrs.symbolize_keys, id: 8, customer_id: 81_721_200, website_id: 7)
            original = site_page.sections.deep_dup
            html = render_inline(described_class.new(page: site_page, website: site, theme: theme))
            images = html.css("main img")

            expect(html).to have_css('main#site-main[tabindex="-1"]')
            expect(html.css('[data-site-section]').size).to eq([11, 9, 5, 6, 3].fetch(index))
            expect(html.css('[data-site-section]').map { |node| node['data-site-section'] }).to eq(original.pluck('id'))
            expect(images.map { |image| File.basename(image['src']) }).to eq(expected_art[index])
            hero_images = html.css("[data-site-section$='_hero'] img")
            expect(hero_images.map { |image| image['loading'] }).to all(eq('eager'))
            expect((images - hero_images).map { |image| image['loading'] }).to all(eq('lazy'))
            if source_page['slug'] == 'about'
              expect(hero_images.size).to eq(1)
              expect(original.find { |section| section['id'] == 'home_site_about_craft' }.fetch('type')).to eq('split_image_text')
              expect(html.css("[data-site-section='home_site_about_craft'] img").size).to eq(1)
            end
            images.each do |image|
              expect(image['alt']).to be_present
              expect(image['class']).to include('object-cover')
              expect(image.parent.css('svg text')).to be_empty
            end
            headline = original.first.dig('props', 'headline')
            expect(html.css('h1 > span').map(&:text)).to eq(headline.split(/\r?\n/))
            expect(html.at_css('h1').text).to eq(headline)
            expect(site_page.sections).to eq(original)
            rendered_sources.concat(images.map { |image| image["src"] })
          end
        end
      end
      expect(rendered_sources.size).to eq(7)
      expect(rendered_sources.uniq.size).to eq(6)
    end
  end

  it 'dispatches known types first, preserves inserted generic sections and skips unknown types in saved order' do
    site = Website.new(id: 7, customer_id: 81_721_200)
    record = WebsitePage.new(id: 8, website_id: 7, customer_id: 81_721_200, home: true, sections: [
      { id: 'quote-first', type: 'quote', props: { quote: 'Owner quote' } },
      { id: 'unknown', type: 'unknown', props: { headline: 'Hidden' } },
      { id: 'custom-hero-id', type: 'hero_centered', props: { headline: "Owner\nHero", media_mode: 'none' } }
    ])
    component = described_class.new(page: record, website: site, theme: theme)
    allow(component.presentation).to receive(:component_class).and_call_original
    expect(component.presentation).not_to receive(:component_class).with('unknown')
    html = render_inline(component)
    expect(html.css('[data-site-section]').map { |node| node['data-site-section'] }).to eq(%w[quote-first custom-hero-id])
    expect(html).to have_text('Owner quote')
    expect(html.css('h1 > span').map(&:text)).to eq(%w[Owner Hero])
    expect(html).not_to have_text('Hidden')
  end

  it 'cannot bypass generic-only fallback with explicit context or a target-looking section ID' do
    target_site = Website.new(id: 7, customer_id: 81_721_200)
    target_page = WebsitePage.new(id: 8, website_id: 7, customer_id: 81_721_200, home: true)
    context = Websites::HomeSite::Presentation.for(website: target_site, page: target_page)
    [
      [target_site, WebsitePage.new(customer_id: 81_721_200, website_id: 7, slug: 'extra')],
      [Website.new(id: 9, customer_id: 42), WebsitePage.new(customer_id: 42, website_id: 9, home: true)],
      [nil, target_page],
      [Website.new(id: 99, customer_id: 81_721_200), target_page]
    ].each do |site, record|
      record.sections = [{ id: 'home_site_home_hero', type: 'hero_centered', props: { headline: 'Literal', media_mode: 'none' } }]
      html = render_inline(described_class.new(page: record, website: site, presentation: context, theme: theme))
      expect(html.css('#site-main, h1 > span')).to be_empty
      expect(html).to have_css('h1', text: 'Literal')
    end
  end
end
