# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeveloperDocs::ReaderComponent, type: :component do
  def entry(slug, title, active: false)
    DeveloperDocs::Repository::Entry.new(
      slug: slug,
      title: title,
      path: "/81721200/admin/maintenance/platform/developer_docs/#{slug}",
      active: active
    )
  end

  def doc_page
    current_group = DeveloperDocs::Repository::Group.new(key: "orientation", entries: [
      entry("overview", "Developer reference", active: true),
      entry("system-map", "System map")
    ])
    DeveloperDocs::Repository::Page.new(
      slug: "overview",
      title: "Developer reference",
      summary: "How the reference is hosted.",
      html: %(<h2 id="summary">Summary</h2><p>Body</p>).html_safe,
      headings: [{ level: 2, id: "summary", text: "Summary" }, { level: 3, id: "adding-a-page", text: "Adding a page" }],
      groups: [current_group],
      current_group: current_group,
      previous_page: nil,
      next_page: DeveloperDocs::Repository::Link.new(slug: "system-map", title: "System map", path: "/81721200/admin/maintenance/platform/developer_docs/system-map"),
      query: "",
      search_path: "/81721200/admin/maintenance/platform/developer_docs"
    )
  end

  it "links the contents, the same-page headings, and the next page" do
    render_inline(described_class.new(page: doc_page))

    expect(page).to have_css("h2#summary", text: "Summary")
    expect(page).to have_link("System map", href: "/81721200/admin/maintenance/platform/developer_docs/system-map")
    expect(page).to have_link("Summary", href: "#summary")
    expect(page).to have_link("Adding a page", href: "#adding-a-page")
    expect(page).to have_css('a[aria-current="page"]', text: "Developer reference")
    expect(page).to have_field("Search the reference")
    expect(page).to have_button("Search")
    expect(page).not_to have_css("input[name='locale']", visible: :all)
  end

  it "shows the empty search state" do
    empty = doc_page.with(query: "zzzz", groups: [])
    render_inline(described_class.new(page: empty))

    expect(page).to have_content("No pages match that search.")
    expect(page).to have_link("Clear search", href: "/81721200/admin/maintenance/platform/developer_docs")
  end

  def customer_page
    root = "/12345678/admin/help/docs"
    groups = CustomerDocs::Catalog.groups.map do |group|
      DeveloperDocs::Repository::Group.new(key: group[:key], entries: group[:pages].map do |slug|
        DeveloperDocs::Repository::Entry.new(slug: slug, title: "Full title: #{slug}", path: "#{root}/#{slug}", active: slug == "forms")
      end)
    end

    doc_page.with(
      slug: "forms",
      title: "Full title: forms",
      groups: groups,
      current_group: groups.find { |group| group.key == "content" },
      previous_page: DeveloperDocs::Repository::Link.new(slug: "records", title: "Find and export records", path: "#{root}/records"),
      next_page: DeveloperDocs::Repository::Link.new(slug: "websites", title: "Publish your website", path: "#{root}/websites"),
      query: "",
      search_path: "#{root}/forms"
    )
  end

  it "uses customer labels for both responsive contents regions and keeps the drawer contract" do
    render_inline(described_class.new(page: customer_page, translation_scope: "customer_docs"))

    expect(page).to have_field("developer-docs-q", placeholder: "Search the guides", with: "")
    expect(page).to have_field("developer-docs-q-mobile", placeholder: "Search the guides", with: "")
    expect(page).to have_css("form[action='/12345678/admin/help/docs/forms'][method='get']", count: 2)
    expect(page).to have_css("input[type='search'][maxlength='80']", count: 2)
    ["Home", "Users", "Content", "Settings"].each do |label|
      expect(page).to have_css("nav h3 > span", exact_text: label, normalize_ws: true, count: 2)
    end
    expect(page).to have_css("a[aria-current='page'][href='/12345678/admin/help/docs/forms']", count: 2)
    expect(page).not_to have_link("Clear search")
    expect(page).to have_link("Get started", href: "/12345678/admin/help/docs/getting-started")
    expect(page).to have_link("Manage users", href: "/12345678/admin/help/docs/users")
    expect(page).to have_css("[data-controller~='developer-docs-nav'][data-developer-docs-nav-open-label-value='Open contents'][data-developer-docs-nav-close-label-value='Close contents']")
    expect(page).to have_css("button[data-action='click->developer-docs-nav#openDrawer'][aria-label='Open contents']")
    expect(page).to have_css("[data-developer-docs-nav-target='drawer'][role='dialog'][aria-modal='true'][aria-label='Contents']")
    expect(page).to have_css("[data-developer-docs-nav-target='backdrop'][data-action='click->developer-docs-nav#closeDrawer']")
    expect(page).to have_css("button[data-action='click->developer-docs-nav#closeDrawer'][aria-label='Close contents']")
    expect(page).to have_css("[data-docs-nav-list='mobile'] a[data-action='click->developer-docs-nav#navigate']", count: 13)
    expect(page).not_to have_css("nav details, nav summary")
  end

  it "resolves the customer namespace at render time in Simplified Chinese" do
    component = described_class.new(page: customer_page.with(query: "workspace"), translation_scope: "customer_docs")

    I18n.with_locale(:"zh-CN") do
      render_inline(component)

      expect(page).to have_css("input[placeholder='搜索指南']", count: 2)
      ["首页", "用户", "内容", "设置"].each do |label|
        expect(page).to have_css("nav h3 > span", exact_text: label, normalize_ws: true, count: 2)
      end
      expect(page).to have_css("nav[aria-label='搜索结果']", count: 2)
      expect(page).to have_css("nav[aria-label='本页内容']", visible: :all, count: 2)
      expect(page).to have_css("nav[aria-label='阅读顺序']", count: 1)
      expect(page).to have_css("[data-developer-docs-nav-open-label-value='打开目录'][data-developer-docs-nav-close-label-value='关闭目录']")
      expect(page).to have_css("button[aria-label='打开目录']", text: "目录")
      expect(page).to have_css("button[aria-label='关闭目录']")
      expect(page).to have_css("[role='dialog'][aria-label='目录']")
      expect(page).to have_link("清除搜索", href: customer_page.search_path)
      expect(page).to have_button("搜索", count: 2)
    end
  end

  %w[en zh-CN].each do |locale|
    it "submits #{locale} from both customer search forms and preserves it when clearing search" do
      localized_page = customer_page.with(query: "workspace", search_path: "#{customer_page.search_path}?locale=#{locale}")

      I18n.with_locale(locale) do
        render_inline(described_class.new(page: localized_page, translation_scope: "customer_docs", locale: locale))

        expect(page).to have_css("form[action='#{localized_page.search_path}'][method='get'] input[type='hidden'][name='locale'][value='#{locale}']", visible: :all, count: 2)
        expect(page).to have_link(I18n.t("customer_docs.search_clear"), href: localized_page.search_path)
      end
    end
  end

  it "keeps the article and reading sequence when customer search has no results" do
    empty = customer_page.with(query: "zzzz", groups: [])
    render_inline(described_class.new(page: empty, translation_scope: "customer_docs"))

    expect(page).to have_css("p", text: "No pages match that search.", count: 2)
    expect(page).to have_css("h2#summary", text: "Summary")
    expect(page).to have_link("Find and export records", href: empty.previous_page.path, exact: false)
    expect(page).to have_link("Publish your website", href: empty.next_page.path, exact: false)
  end

  it "links home and the other pages in the current section" do
    render_inline(described_class.new(
      page: doc_page,
      home_path: "/81721200/admin/maintenance/platform/developer_docs"
    ))

    expect(page).not_to have_link("Reference home")
    expect(page).to have_css("nav[aria-label='More in this section']")
    expect(page).to have_css("nav[aria-label='More in this section']", text: "Orientation")
    expect(page).to have_link("System map", href: "/81721200/admin/maintenance/platform/developer_docs/system-map")
  end

  it "retains ordered unfiltered section mates while search returns a different group" do
    searching = customer_page.with(
      query: "email", groups: [customer_page.groups.find { |group| group.key == "communication" }]
    )
    render_inline(described_class.new(page: searching, translation_scope: "customer_docs", home_path: "/12345678/admin/help/docs"))

    expect(page).not_to have_link("All guides")
    section = page.find("nav[aria-label='More in this section']")
    expect(section.all("a").map { |link| link[:href] }).to eq(["/12345678/admin/help/docs/websites"])
    expect(section).to have_link("Full title: websites")
  end

  it "defaults to reference typography and no homepage directory" do
    component = described_class.new(page: doc_page)
    render_inline(component)

    expect(component.article_variant).to eq(:reference)
    expect(component.home_groups).to be_nil
    expect(page).to have_css("[data-docs-reader-center] .developer-doc", count: 1)
    expect(page).to have_css("nav[aria-label='On this page']", visible: :all, count: 2)
    expect(page).not_to have_css(".customer-doc, #customer-doc-guides-title")
  end

  it "applies the customer article class only to the Markdown wrapper" do
    render_inline(described_class.new(page: customer_page, translation_scope: "customer_docs", article_variant: :customer))

    expect(page).to have_css("[data-docs-reader-center] .customer-doc", count: 1)
    expect(page).not_to have_css(".customer-doc nav, .customer-doc form, .customer-doc header")
    expect(page).to have_css(".customer-doc h2#summary", text: "Summary")
    expect(page).to have_link("Summary", href: "#summary")
    expect(page).to have_css("nav[aria-label='On this page']", visible: :all, count: 2)
    expect(page).not_to have_css(".developer-doc, #customer-doc-guides-title")
  end

  def home_guide_groups
    [DeveloperDocs::Repository::Group.new(key: "entities", entries: [
      CustomerDocs::Repository::Guide.new(slug: "records", title: "Find and export records", summary: "Find the right records and export your results.", path: "/12345678/admin/help/docs/records?locale=en")
    ])]
  end

  it "inserts the homepage directory outside Markdown typography and omits on-this-page navigation" do
    home = customer_page.with(slug: CustomerDocs::Catalog::HOME_SLUG, query: "zzzz", groups: [])
    render_inline(described_class.new(page: home, translation_scope: "customer_docs", locale: "en", article_variant: :customer, home_groups: home_guide_groups))

    center = page.find("[data-docs-reader-center]")
    expect(center).to have_css("section[aria-labelledby='customer-doc-guides-title']")
    expect(center).to have_css(".customer-doc")
    expect(center.all("section[aria-labelledby='customer-doc-guides-title'], .customer-doc").map(&:tag_name)).to eq(["section", "div"])
    expect(page).to have_link("Find and export records", href: "/12345678/admin/help/docs/records?locale=en")
    expect(page).to have_css("p", text: "No pages match that search.", count: 2)
    expect(page).to have_css(".customer-doc h2#summary", text: "Summary")
    expect(page).not_to have_css(".customer-doc #customer-doc-guides-title")
    expect(page).not_to have_css("nav[aria-label='On this page']")
    expect(page).not_to have_link("Choose your next task", href: "#customer-doc-guides-title")
    expect(page).to have_css("form input[name='locale'][value='en']", visible: :all, count: 2)
    expect(page).to have_css("[data-developer-docs-nav-target='drawer'][role='dialog']")
  end

  it "keeps the overview article and navigation when the supplied directory is empty" do
    home = customer_page.with(slug: CustomerDocs::Catalog::HOME_SLUG)
    render_inline(described_class.new(page: home, translation_scope: "customer_docs", article_variant: :customer, home_groups: []))

    expect(page).to have_css("section h2", text: "Browse guides by topic")
    expect(page).to have_content("Guides are temporarily unavailable. Please try again later.")
    expect(page).not_to have_css("nav[aria-label='On this page']")
    expect(page).to have_css(".customer-doc h2#summary", text: "Summary")
    expect(page).to have_link("Find and export records", href: home.previous_page.path, exact: false)
    expect(page).to have_link("Publish your website", href: home.next_page.path, exact: false)
  end

  it "does not infer a homepage directory from the overview slug when home_groups is nil" do
    home = customer_page.with(slug: CustomerDocs::Catalog::HOME_SLUG)
    render_inline(described_class.new(page: home, translation_scope: "customer_docs", article_variant: :customer))

    expect(page).not_to have_css("#customer-doc-guides-title")
    expect(page).not_to have_content("Guides are temporarily unavailable.")
    expect(page).to have_css(".customer-doc h2#summary")
  end

  {
    "en" => { alt: "Records list with search and column controls.", caption: "Search records and choose your columns.", full_size: "View full size", open: "View full size: Search records and choose your columns." },
    "zh-CN" => { alt: "记录列表，包含搜索与列设置控件。", caption: "搜索记录并选择要显示的列。", full_size: "查看原图", open: "查看原图：搜索记录并选择要显示的列。" }
  }.each do |locale, text|
    it "preserves #{locale} renderer figures, native full-size links and natural responsive image proportions" do
      I18n.with_locale(locale) do
        path = "/help/docs/screenshots/#{locale}/records-list.png"
        rendered = DeveloperDocs::Renderer.call(
          "![#{text[:alt]}](#{path} \"#{text[:caption]}\")",
          link_resolver: ->(slug) { "/12345678/admin/help/docs/#{slug}?locale=#{locale}" },
          labels: I18n.t("customer_docs.callouts").stringify_keys,
          anchor_label: I18n.t("customer_docs.anchor"),
          catalog: CustomerDocs::Catalog,
          screenshot_root: "/help/docs/screenshots",
          screenshot_labels: {
            full_size: I18n.t("customer_docs.screenshots.full_size"),
            open: I18n.t("customer_docs.screenshots.open", caption: "%{caption}")
          }
        )
        with_figure = customer_page.with(html: "#{customer_page.html}#{rendered.html}".html_safe)
        render_inline(described_class.new(page: with_figure, translation_scope: "customer_docs", article_variant: :customer))

        expect(page).to have_css(".customer-doc figure > a[aria-label='#{text[:open]}'] img[src='#{path}'][alt='#{text[:alt]}'][loading='lazy'][decoding='async']")
        expect(page).to have_css("figure a[href='#{path}']", count: 2)
        expect(page).to have_css("figcaption span", text: text[:caption])
        expect(page).to have_link(text[:full_size], href: path)
        expect(page).not_to have_css("figure a[target], figure [role='alert']")
        expect(page).to have_css("[data-docs-reader-center] .customer-doc", count: 1)
        expect(page).to have_css(".customer-doc figure img")
        expect(page).not_to have_css(".customer-doc figure img[class*='object-cover']")
      end
    end
  end

  it "renders an optional page header inside the center before article navigation and Markdown" do
    render_inline(described_class.new(page: doc_page)) do |reader|
      reader.with_header do
        vc_test_controller.view_context.render AdminPageComponent.new(breadcrumbs: [], title: doc_page.title, description: doc_page.summary, wrap_title: true, width: "full")
      end
    end

    expect(page).to have_css("h1", count: 1, text: doc_page.title)
    expect(page).to have_css("[data-docs-reader-center] > header h1", text: doc_page.title)
    expect(page).to have_css("[data-docs-reader-center] > header p", text: doc_page.summary)
    expect(page).to have_css("[data-docs-reader-center] > header + [data-docs-inline-toc] details nav[aria-label='On this page']", visible: :all)
    expect(page).not_to have_css(".developer-doc h1, .developer-doc header, .developer-doc nav")
  end

  it "allows standalone readers without a header slot and omits TOCs when there are no headings" do
    render_inline(described_class.new(page: doc_page.with(headings: [], next_page: nil)))

    expect(page).to have_css(".developer-doc h2#summary")
    expect(page).not_to have_css("[data-docs-reader-center] > header, h1, [data-docs-inline-toc], nav[aria-label='On this page']")
  end

  it "renders only available reading-sequence endpoints without empty placeholder children" do
    render_inline(described_class.new(page: doc_page))

    sequence = page.find("[data-docs-footer-sequence]")
    expect(sequence).to have_css("a", count: 1)
    expect(sequence).to have_link("Next System map", href: doc_page.next_page.path, normalize_ws: true)
    expect(sequence.all(:xpath, "./*").map(&:tag_name)).to eq(["a"])
  end

  it "keeps only the previous endpoint on the final page" do
    final_page = doc_page.with(previous_page: doc_page.next_page, next_page: nil)
    render_inline(described_class.new(page: final_page))

    sequence = page.find("[data-docs-footer-sequence]")
    expect(sequence).to have_link("Previous System map", href: final_page.previous_page.path, normalize_ws: true)
    expect(sequence.all(:xpath, "./*").map(&:tag_name)).to eq(["a"])
  end

  %w[en zh-CN].each do |locale|
    ["excluded", "no-results", "current-match"].each do |state|
      it "retains #{locale} context, siblings and sequence for #{state} search without duplicate current semantics" do
        full = customer_page
        results = case state
        when "excluded" then [full.groups.find { |group| group.key == "communication" }]
        when "current-match" then [full.current_group.with(entries: full.current_group.entries.select(&:active))]
        else []
        end
        searching = full.with(query: state, groups: results)
        home_path = "/12345678/admin/help/docs?locale=#{locale}"
        I18n.with_locale(locale) do
          render_inline(described_class.new(page: searching, translation_scope: "customer_docs", home_path: home_path, locale: locale))

          %w[desktop mobile].each do |surface|
            header = page.find("[data-docs-nav-header='#{surface}']")
            list = page.find("[data-docs-nav-list='#{surface}']")
            expect(header).to have_button(I18n.t("customer_docs.search_submit"))
            expect(header).not_to have_link(I18n.t("customer_docs.home_link"))
            expect(header).to have_link(I18n.t("customer_docs.search_clear"), href: searching.search_path)
            expect(header).to have_css("a[aria-current='page'][data-docs-current-guide]", count: 1)
            current = header.find("a[aria-current='page']")
            expect(current.text).to eq(I18n.t("customer_docs.nav_labels.forms"))
            expect(current[:href]).to eq("/12345678/admin/help/docs/forms")
            expect(page).to have_css("##{current[:'aria-describedby']}", exact_text: searching.title, visible: :all)
            expect(header).to have_link(I18n.t("customer_docs.groups.content"), href: "#{home_path}#customer-doc-guide-group-content")
            expect(list).not_to have_css("a[aria-current], [data-docs-current-guide]")
            expect(list.all("li > a").map { |link| link[:href] }).to eq(results.flat_map(&:entries).map(&:path))
          end
          expect(page.find("nav[aria-label='#{I18n.t('customer_docs.more_in_section')}']")).to have_link("Full title: websites")
          footer = page.find("[data-docs-footer-sequence]")
          expect(footer.all("a").map { |link| link[:href] }).to eq([full.previous_page.path, full.next_page.path])
          [full.previous_page, full.next_page].each { |neighbor| expect(footer).to have_text(neighbor.title) }
          ids = page.all("[id]", visible: :all).map { |node| node[:id] }
          expect(ids.uniq).to eq(ids)
        end
      end
    end
  end

  it "omits empty section navigation for a single-guide group and handles absent current-group metadata" do
    single = customer_page.groups.find { |group| group.key == "users" }
    render_inline(described_class.new(page: customer_page.with(current_group: single.with(entries: single.entries.map { |guide| guide.with(active: true) })), translation_scope: "customer_docs"))
    expect(page).not_to have_css("nav[aria-label='More in this section']")

    searching = customer_page.with(query: "missing", groups: [], current_group: nil)
    render_inline(described_class.new(page: searching, translation_scope: "customer_docs"))
    expect(page).not_to have_css("nav[aria-label='More in this section']")
    expect(page).to have_css("[data-docs-nav-header='desktop'] a[aria-current='page'][href='#{searching.search_path}']")
  end

  it "keeps the reading sequence after the prose on hubs and articles, never above the article" do
    render_inline(described_class.new(page: doc_page, home_groups: []))
    expect(page).to have_css("[data-docs-footer-sequence] a", count: 1)

    render_inline(described_class.new(page: doc_page))
    expect(page).to have_css("[data-docs-reader-center] > [data-docs-inline-toc] + .developer-doc")
    expect(page).to have_css("[data-docs-reader-center] > .developer-doc ~ div [data-docs-footer-sequence] a", count: 1)
    expect(page).not_to have_css("[data-docs-top-sequence], h1")
  end

  it "wires the reading aids: doc-set home, search shortcut, scroll-spy links, back to top and code copy" do
    render_inline(described_class.new(page: doc_page, home_path: "/81721200/admin/maintenance/platform/developer_docs"))

    reader = page.find(".docs-page")
    expect(reader["data-controller"].split).to eq(%w[developer-docs-nav docs-reader])
    expect(reader["data-docs-reader-copy-label-value"]).to eq("Copy")
    expect(reader["data-docs-reader-copied-label-value"]).to eq("Copied")
    %w[desktop mobile].each do |surface|
      expect(page).to have_css("[data-docs-nav-header='#{surface}'] a[href='/81721200/admin/maintenance/platform/developer_docs']", text: "Developer reference", visible: :all)
    end
    expect(page).to have_css("input#developer-docs-q[aria-keyshortcuts='/'][data-docs-reader-target='search']")
    expect(page).to have_css("form[role='search']", count: 2)
    expect(page).to have_css("a[data-docs-reader-target='tocLink'][href='#summary']", visible: :all, count: 2)
    expect(page).to have_css("nav[aria-label='On this page'][data-turbo='false'] a[data-docs-reader-target='tocLink']", visible: :all, count: 2 * doc_page.headings.size)
    expect(page).to have_css("[data-docs-reader-center][id='developer-doc-article']")
    expect(page).to have_link("Back to top", href: "#developer-doc-article", visible: :all)
    expect(page).to have_css(".developer-doc[data-docs-reader-target='prose']")
    expect(rendered_content).to match(%r{<template data-docs-reader-target="copyTemplate">\s*<div .*data-docs-code>.*data-action="docs-reader#copy".*data-docs-copy-label aria-live="polite">Copy</span>.*</template>}m)
    expect(page).to have_css("[data-docs-mobile-bar] button[data-developer-docs-nav-target='trigger']", text: "Contents")
    expect(page).to have_css("[data-docs-mobile-bar]", text: "Orientation")
  end

  it "translates the reading aids in Simplified Chinese and omits the doc-set link without a home path" do
    I18n.with_locale(:"zh-CN") do
      render_inline(described_class.new(page: doc_page))

      expect(page).to have_css(".docs-page[data-docs-reader-copy-label-value='复制'][data-docs-reader-copied-label-value='已复制']")
      expect(page).to have_link("返回顶部", visible: :all)
      expect(page).not_to have_css("[data-docs-nav-header='desktop'] a")
      expect(page).not_to have_css("[data-docs-nav-header='mobile'] a", visible: :all)
      expect(page).to have_css("[data-docs-nav-header='mobile'] p[aria-hidden='true']", text: "开发文档", visible: :all)
    end
  end
end
