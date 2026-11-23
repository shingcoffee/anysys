# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeveloperDocs::ContentsNavComponent, type: :component do
  def entry(slug, title, active: false)
    DeveloperDocs::Repository::Entry.new(
      slug: slug,
      title: title,
      path: "/81721200/admin/maintenance/platform/developer_docs/#{slug}",
      active: active
    )
  end

  def page_for(query: "")
    DeveloperDocs::Repository::Page.new(
      slug: "overview",
      title: "Developer reference",
      summary: "How the reference is hosted.",
      html: "".html_safe,
      headings: [],
      groups: [
        DeveloperDocs::Repository::Group.new(key: "orientation", entries: [
          entry("overview", "Developer reference", active: true),
          entry("system-map", "System map")
        ]),
        DeveloperDocs::Repository::Group.new(key: "access", entries: [
          entry("authentication", "Authentication")
        ])
      ],
      current_group: DeveloperDocs::Repository::Group.new(key: "orientation", entries: [
        entry("overview", "Developer reference", active: true), entry("system-map", "System map")
      ]),
      previous_page: nil,
      next_page: nil,
      query: query,
      search_path: "/81721200/admin/maintenance/platform/developer_docs"
    )
  end

  it "lists every group as a labelled section with all pages visible" do
    render_inline(described_class.new(page: page_for, translation_scope: "developer_docs"))

    expect(page).to have_css("nav[aria-label='Contents'] section[aria-labelledby]", count: 2)
    expect(page).not_to have_css("details, summary")
    expect(page).to have_css("section[aria-labelledby='developer-doc-nav-desktop-group-orientation'] > h3#developer-doc-nav-desktop-group-orientation > span", text: "Orientation")
    expect(page).to have_link("Authentication", href: "/81721200/admin/maintenance/platform/developer_docs/authentication")
    expect(page).not_to have_css("a[aria-describedby]")
    expect(page).to have_link("Developer reference", href: "/81721200/admin/maintenance/platform/developer_docs/overview")
    expect(page).to have_css('a[aria-current="page"]', text: "Developer reference")
    expect(page).not_to have_css("a[data-action]")
  end

  it "shows every remaining group while searching" do
    render_inline(described_class.new(page: page_for(query: "auth"), translation_scope: "developer_docs"))

    expect(page).to have_css("nav section", count: 2)
    expect(page).to have_css("nav[aria-label='Search results']")
    expect(page).not_to have_css("a[aria-current], [data-docs-current-guide]")
  end

  it "marks drawer links so the contents panel can close after a choice" do
    render_inline(described_class.new(page: page_for, translation_scope: "developer_docs", navigate: true))

    expect(page).to have_css("a[data-action='click->developer-docs-nav#navigate']", count: 3, visible: :all)
  end

  it "shows the empty search copy when no groups remain" do
    empty = page_for.with(groups: [], query: "zzzz")
    render_inline(described_class.new(page: empty, translation_scope: "developer_docs"))

    expect(page).to have_content("No pages match that search.")
    expect(page).to have_css("nav[aria-label='Search results']")
    expect(page).to have_link("Clear search", href: empty.search_path)
    expect(page).not_to have_css("details, section, h3, [role='alert']")
  end

  it "translates group labels and empty results at render time in Chinese" do
    I18n.with_locale(:"zh-CN") do
      render_inline(described_class.new(page: page_for, translation_scope: "developer_docs"))

      expect(page).to have_css("nav[aria-label='目录'] section h3 > span", text: "导读")
      expect(page).to have_css("nav h3", count: 2)
      expect(page).to have_css("a[aria-current='page']", count: 1)

      render_inline(described_class.new(page: page_for.with(groups: [], query: "zzzz"), translation_scope: "developer_docs"))
      expect(page).to have_content(I18n.t("developer_docs.search_empty"))
      expect(page).to have_css("nav[aria-label='搜索结果']")
      expect(page).to have_link("清除搜索", href: page_for.search_path)
    end
  end

  %w[en zh-CN].each do |locale|
    it "makes every #{locale} customer guide reachable without disclosures with full-title descriptions" do
      groups = CustomerDocs::Catalog.groups.map do |group|
        DeveloperDocs::Repository::Group.new(key: group[:key], entries: group[:pages].map do |slug|
          entry(slug, "Full title: #{slug}", active: slug == "forms")
        end)
      end
      customer = page_for.with(slug: "forms", title: "Full title: forms", groups: groups, current_group: groups.find { |group| group.key == "content" })

      I18n.with_locale(locale) do
        render_inline(described_class.new(page: customer, translation_scope: "customer_docs"))

        expect(page).not_to have_css("details, summary")
        expect(page).to have_css("nav section[aria-labelledby] > h3", count: 8)
        expect(page.all("ul > li > a").map { |link| link[:href] }).to eq(groups.flat_map(&:entries).map(&:path))
        expect(page).to have_css("a[aria-current='page'][data-docs-current-guide]", count: 1)
        groups.flat_map(&:entries).each do |guide|
          link = page.find("a[href='#{guide.path}']")
          expect(link.text.strip).to eq(I18n.t("customer_docs.nav_labels.#{guide.slug}"))
          expect(link[:'aria-label']).to be_nil
          expect(page).to have_css("##{link[:'aria-describedby']}", exact_text: guide.title, visible: :all)
        end
      end
    end

    it "keeps a current-match result ordinary and visibly describes its #{locale} short label" do
      matching = entry("forms", "Full form guide title", active: true)
      filtered = page_for.with(query: "form", groups: [DeveloperDocs::Repository::Group.new(key: "content", entries: [matching])])
      I18n.with_locale(locale) do
        render_inline(described_class.new(page: filtered, translation_scope: "customer_docs", surface: :mobile, navigate: true))

        expect(page).to have_css("nav[aria-label='#{I18n.t('customer_docs.search_results')}'] li > a", count: 1)
        link = page.find("li > a")
        expect(link).to have_text(I18n.t("customer_docs.nav_labels.forms"))
        expect(link).to have_css("##{link[:'aria-describedby']}", exact_text: matching.title)
        expect(link[:'data-action']).to eq("click->developer-docs-nav#navigate")
        expect(link[:'aria-current']).to be_nil
        expect(link[:'data-docs-current-guide']).to be_nil
      end
    end
  end

  it "scopes description and group-heading IDs independently for the two surfaces" do
    customer = page_for.with(groups: [DeveloperDocs::Repository::Group.new(key: "content", entries: [entry("forms", "Full form title", active: true)])])
    renders = %i[desktop mobile].map do |surface|
      render_inline(described_class.new(page: customer, translation_scope: "customer_docs", surface: surface))
      Nokogiri::HTML.fragment(rendered_content)
    end
    ids = renders.flat_map { |dom| dom.css("[id]").map { |node| node["id"] } }
    expect(ids.uniq).to eq(ids)
    renders.each do |dom|
      described = dom.at_css("a[aria-describedby]")
      expect(dom.at_css("##{described['aria-describedby']}").text).to eq("Full form title")
      group = dom.at_css("section[aria-labelledby]")
      expect(group.at_css("##{group['aria-labelledby']}")).not_to be_nil
    end
  end
end
