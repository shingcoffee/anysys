# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe CustomerDocs::Repository do
  let(:content_root) { @content_root }
  let(:route_helpers) { double("documentation route helpers") }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:repository) { build_repository }

  def write_source(slug, locale: "en", title: "Guide #{slug}", summary: "Customer task", body: "## Steps\n\nManage your workspace.")
    path = content_root.join(locale, "#{slug}.md")
    File.write(path, "---\ntitle: #{title}\nsummary: #{summary}\n---\n#{body}\n")
    path
  end

  def build_repository(**options)
    described_class.new(customer_id: "123", locale: :en, content_root: content_root, **options)
  end

  around do |example|
    Dir.mktmpdir("customer-docs", Rails.root.join("tmp")) do |directory|
      @content_root = Pathname.new(directory)
      %w[en zh-CN].each { |locale| @content_root.join(locale).mkpath }
      example.run
    end
  end

  before do
    allow(Rails).to receive(:cache).and_return(cache)
    allow(Rails.application.routes).to receive(:url_helpers).and_return(route_helpers)
    allow(route_helpers).to receive(:admin_help_doc_path) do |customer_id, slug, **options|
      path = "/#{customer_id}/admin/help/docs/#{slug}"
      options.empty? ? path : "#{path}?#{options.to_query}"
    end
    allow(route_helpers).to receive(:alternate_doc_path) { |customer_id, slug| "/#{customer_id}/admin/alternate/docs/#{slug}" }

    backend = I18n::Backend::Simple.new
    backend.eager_load!
    backend.store_translations(:en, customer_docs: {
      anchor: "Customer section link", callouts: { attention: "Important", note: "Customer note" },
      screenshots: { full_size: "View full size", open: "View full size: %{caption}" }
    }, alternate_docs: {
      anchor: "Alternate section link", callouts: { attention: "Alternate important", note: "Alternate note" }
    })
    backend.store_translations(:"zh-CN", customer_docs: {
      anchor: "本节链接", callouts: { attention: "重要提示", note: "说明" },
      screenshots: { full_size: "查看原图", open: "查看原图：%{caption}" }
    })
    allow(I18n.config).to receive(:backend).and_return(backend)

    write_source("overview", title: "Customer documentation", body: <<~MD)
      ## Steps

      [Get started](getting-started#steps)
      [Developer guide](entity-builder)

      :::attention
      Check your workspace first.
      :::

      :::note
      Save your changes.
      :::
    MD
    write_source("getting-started", title: "Get started", body: "## Steps\n\nInvite your team.")
    write_source("forms", title: "Collect responses", summary: "Create a FORM")
    write_source("support", title: "Contact support")
  end

  it "uses the customer content root by default" do
    root = content_root.join("application")
    target = root.join("doc/customer/en")
    target.mkpath
    File.write(target.join("overview.md"), "---\ntitle: Default customer guide\nsummary: Customer root\n---\n## Steps\n")
    allow(Rails).to receive(:root).and_return(root)

    page = described_class.new(customer_id: "123", locale: :en).page("overview")

    expect(page.title).to eq("Default customer guide")
    expect(page.search_path).to eq("/123/admin/help/docs/overview")
  end

  it "builds customer groups, active state, reading sequence, search path, and article links" do
    page = repository.page("getting-started", search_path: "/123/admin/help/docs")

    expect(page.groups.map(&:key)).to eq(%w[home content settings])
    entries = page.groups.flat_map(&:entries)
    expect(entries.map(&:slug)).to eq(%w[overview getting-started forms support])
    expect(entries.select(&:active).map(&:slug)).to eq(["getting-started"])
    expect(entries.map(&:path)).to all(start_with("/123/admin/help/docs/"))
    expect(page.current_group.key).to eq("home")
    expect(page.current_group.entries.map(&:slug)).to eq(%w[overview getting-started])
    expect(page.current_group.entries.select(&:active).map(&:slug)).to eq(["getting-started"])
    expect(page.previous_page.slug).to eq("overview")
    expect(page.previous_page.path).to eq("/123/admin/help/docs/overview")
    expect(page.next_page.slug).to eq("forms")
    expect(page.next_page.path).to eq("/123/admin/help/docs/forms")
    expect(page.search_path).to eq("/123/admin/help/docs")

    overview = repository.page("overview")
    expect(overview.previous_page).to be_nil
    expect(overview.html).to include('href="/123/admin/help/docs/getting-started#steps"')
    expect(overview.html).not_to include("entity-builder", "developer_docs")
    expect(repository.page("support").next_page).to be_nil
  end

  it "searches localized titles, summaries, and bodies without changing the article or neighbors" do
    page = repository.page("getting-started", query: "  fOrM  ")

    expect(page.query).to eq("fOrM")
    expect(page.groups.flat_map(&:entries).map(&:slug)).to eq(["forms"])
    expect(page.title).to eq("Get started")
    expect(page.previous_page.path).to eq("/123/admin/help/docs/overview")
    expect(page.next_page.path).to eq("/123/admin/help/docs/forms")
    expect(repository.page("overview", query: "team").groups.flat_map(&:entries).map(&:slug)).to eq(["getting-started"])
    expect(repository.page("overview", query: "contact").groups.flat_map(&:entries).map(&:slug)).to eq(["support"])
    expect(repository.page("overview", query: "x" * 100).query.length).to eq(80)
    expect(repository.page("overview", query: "no matching task").groups).to be_empty
  end

  it "keeps the full current group and reading sequence independent of matching and empty results" do
    write_source("websites", title: "Publish a website")
    unfiltered = repository.page("forms")

    ["team", "no matching task"].each do |query|
      page = repository.page("forms", query: query)

      expect(page.groups.flat_map(&:entries).map(&:slug)).to eq(query == "team" ? ["getting-started"] : [])
      expect(page.current_group).to eq(unfiltered.current_group)
      expect(page.current_group.key).to eq("content")
      expect(page.current_group.entries.map(&:slug)).to eq(%w[forms websites])
      expect(page.current_group.entries.select(&:active).map(&:slug)).to eq(["forms"])
      expect(page.previous_page).to eq(unfiltered.previous_page)
      expect(page.next_page).to eq(unfiltered.next_page)
      expect(page.previous_page.to_h).to eq(slug: "getting-started", title: "Get started",
                                          path: "/123/admin/help/docs/getting-started")
      expect(page.next_page.to_h).to eq(slug: "websites", title: "Publish a website",
                                      path: "/123/admin/help/docs/websites")
      expect(page.html).to eq(unfiltered.html)
    end
  end

  it "omits missing siblings from current context and reading order without inventing results" do
    page = repository.page("forms", query: "team")

    expect(page.current_group.entries.map(&:slug)).to eq(["forms"])
    expect(page.current_group.entries.select(&:active).map(&:slug)).to eq(["forms"])
    expect(page.next_page.slug).to eq("support")
    expect(page.groups.flat_map(&:entries).map(&:slug)).to eq(["getting-started"])
  end

  it "returns complete contents for a blank query with only one active current-group entry" do
    page = repository.page("getting-started", query: " \t\n ")

    expect(page.query).to eq("")
    expect(page.groups.flat_map(&:entries).map(&:slug)).to eq(%w[overview getting-started forms support])
    expect(page.current_group).to eq(page.groups.first)
    expect(page.current_group.entries.select(&:active).map(&:slug)).to eq(["getting-started"])
  end

  it "drops both query route keys from metadata navigation while preserving URL tenant, locale, and other options" do
    route_options = { q: "symbol query", "q" => "string query", "locale" => "zh-CN", section: "guides" }
    page = build_repository(customer_id: "456", locale: :"zh-CN", route_options: route_options)
      .page("getting-started", query: "FORM", search_path: "/456/admin/help/docs/getting-started?locale=zh-CN")
    paths = page.groups.flat_map(&:entries).map(&:path) + page.current_group.entries.map(&:path) +
            [page.previous_page.path, page.next_page.path]

    expect(paths).to all(start_with("/456/admin/help/docs/"))
    expect(paths).to all(end_with("?locale=zh-CN&section=guides"))
    paths.each { |path| expect(path).not_to include("q=", "/123/", "81721200") }
    expect(page.search_path).to eq("/456/admin/help/docs/getting-started?locale=zh-CN")
    expect(build_repository(customer_id: "456", route_options: route_options).page("getting-started").search_path)
      .to eq("/456/admin/help/docs/getting-started?locale=zh-CN&section=guides")
    expect(route_options).to eq(q: "symbol query", "q" => "string query", "locale" => "zh-CN", section: "guides")
  end

  it "rejects developer-only, unknown, and traversal slugs before reading files" do
    write_source("entity-builder")
    expect(File).not_to receive(:read)

    ["entity-builder", "not-a-guide", "../overview", "overview.md", "/overview", nil].each do |slug|
      expect(repository.page(slug)).to be_nil
    end
  end

  it "returns nil for an allow-listed guide without a source" do
    expect(repository.page("users")).to be_nil
  end

  it "uses the requested locale for article content, search, callouts, and anchors" do
    write_source("overview", locale: "zh-CN", title: "客户文档", body: "## 操作步骤\n\n:::attention\n请确认当前客户。\n:::\n\n:::note\n请保存。\n:::")
    write_source("getting-started", locale: "zh-CN", title: "开始使用", body: "## 操作步骤\n\n邀请团队。")

    I18n.with_locale(:en) do
      page = build_repository(locale: :"zh-CN").page("overview", query: "团队")

      expect(page.title).to eq("客户文档")
      expect(page.headings.first[:text]).to eq("操作步骤")
      expect(page.html).to include("重要提示", "说明", 'aria-label="本节链接"')
      expect(page.html).not_to include("Important", "Customer section link")
      expect(page.groups.flat_map(&:entries).map(&:slug)).to eq(["getting-started"])
      expect(page.current_group.entries.map(&:title)).to eq(["客户文档", "开始使用"])
      expect(page.current_group.entries.select(&:active).map(&:slug)).to eq(["overview"])
      expect(page.next_page.to_h).to eq(slug: "getting-started", title: "开始使用", path: "/123/admin/help/docs/getting-started")
      expect(I18n.locale).to eq(:en)
    end
  end

  it "falls back to English sources while keeping labels in the requested locale" do
    I18n.with_locale(:en) do
      page = build_repository(locale: :"zh-CN").page("overview")

      expect(page.title).to eq("Customer documentation")
      expect(page.html).to include("重要提示", "说明", 'aria-label="本节链接"')
      expect(page.current_group.entries.map(&:title)).to eq(["Customer documentation", "Get started"])
    end
  end

  it "normalizes unsupported locales and uses English labels despite the ambient locale" do
    I18n.with_locale(:"zh-CN") do
      page = build_repository(locale: :fr).page("overview")

      expect(page.title).to eq("Customer documentation")
      expect(page.html).to include("Important", "Customer note", 'aria-label="Customer section link"')
      expect(page.html).not_to include("重要提示", "本节链接")
    end
  end

  it "isolates cached article paths by tenant and labels by requested locale, including source fallback" do
    first = repository.page("overview")
    second = build_repository(customer_id: "456").page("overview")
    chinese = build_repository(locale: :"zh-CN").page("overview")

    expect(first.html).to include('href="/123/admin/help/docs/getting-started#steps"')
    expect(second.html).to include('href="/456/admin/help/docs/getting-started#steps"')
    expect(second.html).not_to include("/123/")
    expect(chinese.html).to include("重要提示", 'aria-label="本节链接"')
    expect(chinese.html).not_to include("Important", "Customer section link")
  end

  it "isolates cached rendering when the catalog, translation scope, or route helper changes" do
    repository.page("overview")
    alternate_labels = build_repository(translation_scope: "alternate_docs").page("overview")
    alternate_route = build_repository(route_helper: :alternate_doc_path).page("overview")
    developer_catalog = build_repository(catalog: DeveloperDocs::Catalog).page("overview")

    expect(alternate_labels.html).to include("Alternate important", 'aria-label="Alternate section link"')
    expect(alternate_labels.html).to include('href="/123/admin/help/docs/getting-started#steps"')
    expect(alternate_route.html).to include('href="/123/admin/alternate/docs/getting-started#steps"')
    expect(alternate_route.html).not_to include("/admin/help/")
    expect(developer_catalog.html).to include('href="/123/admin/help/docs/entity-builder"')
    expect(developer_catalog.html).not_to include('href="/123/admin/help/docs/getting-started#steps"')
  end

  it "reuses cached rendering across repository instances with the same configuration" do
    original = repository.page("overview")
    expect(DeveloperDocs::Renderer).not_to receive(:call)

    cached = build_repository.page("overview")

    expect(cached.html).to eq(original.html)
    expect(cached.html).to be_html_safe
    expect(cached.headings).to eq(original.headings)
  end

  it "refreshes current-group and neighbor metadata on the next request while reusing article HTML" do
    original = repository.page("getting-started")
    path = content_root.join("en/getting-started.md")
    timestamp = File.mtime(path)
    write_source("getting-started", title: "Set up your workspace", summary: "Updated task")
    File.utime(timestamp, timestamp, path)
    write_source("overview", title: "Fresh customer documentation")
    write_source("forms", title: "Publish a form", summary: "New response workflow")
    expect(DeveloperDocs::Renderer).not_to receive(:call)

    page = build_repository.page("getting-started", query: "workflow")

    expect(page.html).to eq(original.html)
    expect(page.title).to eq("Set up your workspace")
    expect(page.summary).to eq("Updated task")
    expect(page.current_group.entries.map(&:title)).to eq(["Fresh customer documentation", "Set up your workspace"])
    expect(page.groups.flat_map(&:entries).map(&:title)).to eq(["Publish a form"])
    expect(page.previous_page.title).to eq("Fresh customer documentation")
    expect(page.next_page.title).to eq("Publish a form")
  end

  it "isolates cached article links by route options without changing the content locale" do
    default = repository.page("overview")
    english = build_repository(route_options: { locale: :en }).page("overview")
    chinese = build_repository(route_options: { locale: :"zh-CN" }).page("overview")

    expect(default.html).to include('href="/123/admin/help/docs/getting-started#steps"')
    expect(english.html).to include('href="/123/admin/help/docs/getting-started?locale=en#steps"')
    expect(chinese.html).to include('href="/123/admin/help/docs/getting-started?locale=zh-CN#steps"')
    expect(chinese.html).to include("Customer section link")
    expect(chinese.groups.flat_map(&:entries).map(&:path)).to all(end_with("?locale=zh-CN"))
    expect(chinese.next_page.path).to eq("/123/admin/help/docs/getting-started?locale=zh-CN")
    expect(chinese.search_path).to eq("/123/admin/help/docs/overview?locale=zh-CN")
    expect(build_repository(route_options: { locale: :"zh-CN" }).page("getting-started").previous_page.path)
      .to eq("/123/admin/help/docs/overview?locale=zh-CN")

    expect(DeveloperDocs::Renderer).not_to receive(:call)
    expect(build_repository.page("overview").html).to eq(default.html)
    expect(build_repository(route_options: { locale: :en }).page("overview").html).to eq(english.html)
    expect(build_repository(route_options: { locale: :"zh-CN" }).page("overview").html).to eq(chinese.html)
  end

  it "isolates cached rendering by content root even when slugs and timestamps match" do
    repository.page("overview")
    alternate_root = content_root.join("alternate")
    alternate_root.join("en").mkpath
    alternate_path = alternate_root.join("en/overview.md")
    File.write(alternate_path, "---\ntitle: Alternate content\nsummary: Another root\n---\n## Steps\n\nDifferent content.\n")
    timestamp = File.mtime(content_root.join("en/overview.md"))
    File.utime(timestamp, timestamp, alternate_path)

    page = build_repository(content_root: alternate_root).page("overview")

    expect(page.html).to include("Different content.")
    expect(page.html).not_to include("Check your workspace first.")
  end

  it "invalidates rendered cache for edits within the same second" do
    path = content_root.join("en/overview.md")
    first_timestamp = Time.at(1_800_000_000, 100_000, :microsecond)
    second_timestamp = Time.at(1_800_000_000, 200_000, :microsecond)
    File.utime(first_timestamp, first_timestamp, path)
    original = repository.page("overview")
    write_source("overview", body: "## Steps\n\nUpdated instructions.")
    File.utime(second_timestamp, second_timestamp, path)

    updated = build_repository.page("overview")

    expect(original.html).to include("Check your workspace first.")
    expect(updated.html).to include("Updated instructions.")
    expect(updated.html).not_to include("Check your workspace first.")
  end

  describe "#guide_groups" do
    it "returns all twelve non-home guides in catalog order as immutable metadata" do
      CustomerDocs::Catalog.slugs.each do |slug|
        write_source(slug, title: "Task #{slug}", summary: "Outcome #{slug}")
      end
      expect(DeveloperDocs::Renderer).not_to receive(:call)

      groups = repository.guide_groups
      guides = groups.flat_map(&:entries)

      expect(groups.map(&:key)).to eq(%w[home assistant users payments communication entities content settings])
      expect(groups).to all(be_a(DeveloperDocs::Repository::Group))
      expect(groups.first.entries.map(&:slug)).to eq(["getting-started"])
      expect(guides.map(&:slug)).to eq(CustomerDocs::Catalog.slugs - ["overview"])
      expect(guides.size).to eq(12)
      expect(guides).to all(be_a(described_class::Guide))
      expect(guides.map(&:title)).to eq(guides.map { |guide| "Task #{guide.slug}" })
      expect(guides.map(&:summary)).to eq(guides.map { |guide| "Outcome #{guide.slug}" })
      expect(guides.map(&:path)).to eq(guides.map { |guide| "/123/admin/help/docs/#{guide.slug}?locale=en" })
      expect(guides).to all(be_frozen)
      expect(groups.map(&:entries)).to all(be_frozen)
      expect(guides.flat_map { |guide| guide.to_h.values }).to all(be_frozen)
      expect { guides.first.title.replace("Changed") }.to raise_error(FrozenError)
    end

    it "omits unavailable guides and empty groups" do
      groups = repository.guide_groups

      expect(groups.map(&:key)).to eq(%w[home content settings])
      expect(groups.flat_map(&:entries).map(&:slug)).to eq(%w[getting-started forms support])
      %w[getting-started forms support].each { |slug| File.delete(content_root.join("en", "#{slug}.md")) }
      expect(build_repository.guide_groups).to eq([])
    end

    it "uses localized front matter and English fallback while retaining the effective locale in URLs" do
      write_source("getting-started", locale: "zh-CN", title: "开始使用", summary: "完成工作区设置。")

      guides = build_repository(locale: :"zh-CN").guide_groups.flat_map(&:entries)

      expect(guides.first.title).to eq("开始使用")
      expect(guides.first.summary).to eq("完成工作区设置。")
      expect(guides.find { |guide| guide.slug == "forms" }.title).to eq("Collect responses")
      expect(guides.map(&:path)).to all(end_with("?locale=zh-CN"))
      expect(build_repository(locale: :fr).guide_groups.flat_map(&:entries).map(&:path)).to all(end_with("?locale=en"))
    end

    it "remains complete when search matches only a body or has no results" do
      expected = repository.guide_groups
      page = repository.page("overview", query: "team")

      expect(page.groups.flat_map(&:entries).map(&:slug)).to eq(["getting-started"])
      expect(repository.guide_groups).to eq(expected)
      expect(repository.page("overview", query: "missing query").groups).to be_empty
      expect(repository.guide_groups).to eq(expected)
    end

    it "resolves the URL customer and effective locale without carrying query or locale overrides" do
      guides = build_repository(customer_id: "456", locale: :en,
                                route_options: { locale: :"zh-CN", q: "team" }).guide_groups.flat_map(&:entries)

      expect(guides.map(&:path)).to eq(guides.map { |guide| "/456/admin/help/docs/#{guide.slug}?locale=en" })
      guides.each { |guide| expect(guide.path).not_to include("81721200", "q=", "zh-CN") }
    end

    it "reads metadata edits on the next request without rendering or reusing article metadata" do
      original = repository.guide_groups.flat_map(&:entries).find { |guide| guide.slug == "forms" }
      repository.page("forms")
      path = content_root.join("en/forms.md")
      timestamp = File.mtime(path)
      write_source("forms", title: "Publish a form", summary: "Share a response link.")
      File.utime(timestamp, timestamp, path)
      expect(DeveloperDocs::Renderer).not_to receive(:call)

      updated = build_repository.guide_groups.flat_map(&:entries).find { |guide| guide.slug == "forms" }

      expect(original.summary).to eq("Create a FORM")
      expect(updated.title).to eq("Publish a form")
      expect(updated.summary).to eq("Share a response link.")
    end
  end

  describe "customer screenshot configuration" do
    let(:source) { "/help/docs/screenshots/en/forms-publishing.png" }

    before do
      write_source("forms", body: %(![Visible controls](#{source} "Check launch status.")))
    end

    it "opts into screenshots and resolves localized labels at render time despite the ambient locale" do
      I18n.with_locale(:"zh-CN") do
        english = Nokogiri::HTML5.fragment(repository.page("forms").html)

        expect(english.at_css("img")["src"]).to eq(source)
        expect(english.at_css("figure > a")["aria-label"]).to eq("View full size: Check launch status.")
        expect(english.at_css("figcaption > a").text).to eq("View full size")
      end

      write_source("forms", locale: "zh-CN", title: "发布表单", body: <<~MD)
        ![发布状态及访问范围](/help/docs/screenshots/zh-CN/forms-publishing.png "分享前请核对访问范围。")
      MD
      I18n.with_locale(:en) do
        chinese = Nokogiri::HTML5.fragment(build_repository(locale: :"zh-CN").page("forms").html)

        expect(chinese.at_css("img")["src"]).to eq("/help/docs/screenshots/zh-CN/forms-publishing.png")
        expect(chinese.at_css("figure > a")["aria-label"]).to eq("查看原图：分享前请核对访问范围。")
        expect(chinese.at_css("figcaption > a").text).to eq("查看原图")
      end
    end

    it "keeps fallback-source captions with requested-locale screenshot labels" do
      fragment = Nokogiri::HTML5.fragment(build_repository(locale: :"zh-CN").page("forms").html)

      expect(fragment.at_css("img")["src"]).to eq(source)
      expect(fragment.at_css("figure > a")["aria-label"]).to eq("查看原图：Check launch status.")
      expect(fragment.at_css("figcaption > a").text).to eq("查看原图")
    end

    it "isolates enabled and explicitly disabled cached rendering in either request order" do
      stripped = build_repository(screenshot_root: nil).page("forms")
      enabled = repository.page("forms")

      expect(stripped.html).not_to include("<img", "<figure", "View full size")
      expect(enabled.html).to include("<figure", %(src="#{source}"), "View full size")
      expect(DeveloperDocs::Renderer).not_to receive(:call)
      expect(build_repository(screenshot_root: nil).page("forms").html).to eq(stripped.html)
      expect(build_repository.page("forms").html).to eq(enabled.html)
    end

    it "isolates cached rendering when supplied screenshot labels change" do
      original = repository.page("forms")
      localized = build_repository(screenshot_labels: { full_size: "查看原图", open: "查看原图：%{caption}" }).page("forms")

      expect(original.html).to include("View full size")
      expect(localized.html).to include("查看原图：Check launch status.")
      expect(localized.html).not_to include("View full size")
    end

    it "invalidates screenshot rendering after a source edit" do
      original = repository.page("forms")
      path = content_root.join("en/forms.md")
      timestamp = File.mtime(path) + 0.001
      write_source("forms", body: '![Updated controls](/help/docs/screenshots/en/forms-access.png "Check access.")')
      File.utime(timestamp, timestamp, path)

      updated = build_repository.page("forms")

      expect(original.html).to include(source)
      expect(updated.html).to include("/help/docs/screenshots/en/forms-access.png", "Check access.")
      expect(updated.html).not_to include(source)
    end
  end
end
