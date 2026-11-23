# frozen_string_literal: true

require "rails_helper"

RSpec.describe CustomerDocs::HomeGuidesComponent, type: :component do
  let(:guide_type) { CustomerDocs::Repository::Guide }
  let(:groups) do
    CustomerDocs::Catalog.groups.map do |group|
      entries = group[:pages].reject { |slug| slug == CustomerDocs::Catalog::HOME_SLUG }.map do |slug|
        guide_type.new(
          slug: slug, title: "Task: #{slug}", summary: "Outcome: #{slug}",
          path: "/23456789/admin/help/docs/#{slug}?locale=en"
        )
      end
      DeveloperDocs::Repository::Group.new(key: group[:key], entries: entries)
    end
  end

  it "renders the complete supplied directory in catalog order with metadata and resolved tenant paths" do
    render_inline(described_class.new(groups: groups))

    expect(page).to have_css("section[aria-labelledby='customer-doc-guides-title'] h2#customer-doc-guides-title", text: "Browse guides by topic")
    expect(page).to have_content("Pick a job below, or use Contents to jump to a guide.")
    expect(page).to have_content("Find, inspect, and export records.")
    expect(page).to have_css("a", count: 12)
    expect(page.all("a").map { |link| link[:href] }).to eq(groups.flat_map(&:entries).map(&:path))
    expect(page.all("h3").map(&:text)).to eq(["Home", "AI Assistant", "Users", "Payments", "Communication", "Entities", "Content", "Settings"])
    groups.flat_map(&:entries).each do |guide|
      expect(page).to have_link(guide.title, href: guide.path)
      expect(page).to have_css("p#customer-doc-guide-#{guide.slug}-summary", text: guide.summary)
    end
    expect(page).not_to have_css("a[href*='/overview']")
    expect(page).not_to have_css("a[href*='q=']")
  end

  it "gives every guide row one native link named by its title and described by its summary" do
    render_inline(described_class.new(groups: groups))

    groups.flat_map(&:entries).each do |guide|
      link = page.find("a[href='#{guide.path}']")
      expect(link[:"aria-labelledby"]).to eq("customer-doc-guide-#{guide.slug}-title")
      expect(link[:"aria-describedby"]).to eq("customer-doc-guide-#{guide.slug}-summary")
      expect(link).to have_css("h4##{link[:'aria-labelledby']}", text: guide.title)
      expect(link).to have_css("p##{link[:'aria-describedby']}", text: guide.summary)
      expect(link).to have_css("svg[aria-hidden='true']")
      expect(link).not_to have_css(".card")
      expect(link.find(:xpath, "ancestor::*[contains(concat(' ', normalize-space(@class), ' '), ' card ')]")).to have_css("h3")
      expect(link).not_to have_css("a, button")
      expect(link[:target]).to be_nil
    end
  end

  it "groups all guide rows in one panel per section without truncating metadata" do
    render_inline(described_class.new(groups: groups))

    expect(page).to have_css(".card", count: groups.size)
    page.all(".card").zip(groups).each do |panel, group|
      expect(panel[:id]).to eq("customer-doc-guide-group-#{group.key}")
      expect(panel).to have_css("h3", count: 1)
      expect(panel.all("ul > li > a").map { |link| link[:href] }).to eq(group.entries.map(&:path))
      expect(panel).not_to have_css(".card")
    end
    expect(page).to have_css(".card ul > li:only-child", count: 5)
    expect(page).to have_css(".card ul > li:only-child a[href='#{groups.first.entries.first.path}']")
    expect(page).to have_css("a h4 + p", count: 12)
    expect(page).not_to have_css("[class*='truncate'], [class*='line-clamp'], [class*='scale-']")
  end

  it "heads each topic panel with a decorative icon tile that reuses the matching top-menu icon" do
    render_inline(described_class.new(groups: groups))

    page.all(".card").zip(groups).each do |panel, group|
      tile = panel.find("span[aria-hidden='true']", match: :first)
      expect(tile).to have_css("svg path[d='#{described_class::GROUP_ICONS.fetch(group.key)}']")
      expect(tile).to have_xpath("following-sibling::h3")
    end
    expect(page.find("#customer-doc-guide-group-content span[aria-hidden='true'] svg path")[:d]).to eq(MenuIconComponent::PATHS[:pages])
  end

  it "falls back to a document icon for a topic without a mapped icon" do
    group = DeveloperDocs::Repository::Group.new(key: "unmapped", entries: [])

    expect(described_class.new(groups: [group]).group_icon_path(group)).to eq(described_class::DEFAULT_GROUP_ICON)
  end

  it "maps every customer and developer catalog topic to an icon" do
    keys = (CustomerDocs::Catalog.groups + DeveloperDocs::Catalog.groups).map { |group| group[:key] }
    expect(described_class::GROUP_ICONS.keys).to include(*keys)
  end

  it "resolves Chinese UI labels at render time and uses the supplied Chinese metadata unchanged" do
    guide = guide_type.new(slug: "records", title: "查找并导出记录", summary: "筛选所需记录，调整列表列并导出结果。", path: "/23456789/admin/help/docs/records?locale=zh-CN")
    component = described_class.new(groups: [DeveloperDocs::Repository::Group.new(key: "entities", entries: [guide])])

    I18n.with_locale(:"zh-CN") do
      render_inline(component)

      expect(page).to have_css("h2", text: "按主题浏览指南")
      expect(page).to have_content("从下方任务进入，或通过目录跳转。")
      expect(page).to have_css("h3", text: "实体")
      expect(page).to have_content("查找、查看并导出记录。")
      expect(page).to have_link(guide.title, href: guide.path)
      expect(page).to have_css("p", text: guide.summary)
    end
  end

  { "en" => "Guides are temporarily unavailable. Please try again later.", "zh-CN" => "指南暂时不可用，请稍后重试。" }.each do |locale, message|
    it "shows the directory-unavailable state in #{locale}" do
      component = described_class.new(groups: [])

      I18n.with_locale(locale) do
        render_inline(component)

        expect(page).to have_css("h2", text: I18n.t("customer_docs.home.guides_title"))
        expect(page).to have_css("p", text: message)
        expect(page).not_to have_css("a, ul")
      end
    end
  end

  it "uses the developer heading id and topic copy when the reference scope is supplied" do
    guide = guide_type.new(slug: "system-map", title: "System map", summary: "How the pieces connect.", path: "/81721200/admin/maintenance/platform/developer_docs/system-map")
    render_inline(described_class.new(
      groups: [DeveloperDocs::Repository::Group.new(key: "orientation", entries: [guide])],
      translation_scope: "developer_docs"
    ))

    expect(page).to have_css("h2#developer-doc-guides-title", text: "Browse by topic")
    expect(page).to have_content("Open a capability page, or pick one from Contents.")
    expect(page).to have_content("How the product is structured and how to read this reference.")
    expect(page).to have_css("h4#developer-doc-guide-system-map-title", text: "System map")
    expect(page).to have_css("#developer-doc-guide-group-orientation h3", text: "Orientation")
    expect(page).not_to have_css("#customer-doc-guides-title")
  end

  it "escapes front-matter text rather than treating titles or summaries as markup" do
    guide = guide_type.new(slug: "records", title: "<script>alert('title')</script>", summary: "<img src=x onerror=alert('summary')>", path: "/23456789/admin/help/docs/records?locale=en")
    render_inline(described_class.new(groups: [DeveloperDocs::Repository::Group.new(key: "entities", entries: [guide])]))

    expect(page).to have_css("h4", exact_text: guide.title)
    expect(page).to have_css("p", exact_text: guide.summary)
    expect(page).not_to have_css("script, img")
  end
end
