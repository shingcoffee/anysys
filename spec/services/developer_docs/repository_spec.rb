# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe DeveloperDocs::Repository do
  let(:repository) { described_class.new(customer_id: "81721200", locale: :en) }

  it "renders the overview page and links the next catalog page" do
    page = repository.page("overview", search_path: "/81721200/admin/maintenance/platform/developer_docs")

    expect(page.title).to eq("Developer reference")
    expect(page.html).to include("id=\"summary\"")
    expect(page.headings.map { |heading| heading[:text] }).to include("Summary", "Flow", "Implementation", "Where to pay attention", "Key code")
    expect(page.next_page.slug).to eq("system-map")
    expect(page.next_page.title).to eq("System map")
    expect(page.next_page.path).to eq("/81721200/admin/maintenance/platform/developer_docs/system-map")
    expect(page.previous_page).to be_nil
  end

  it "filters the contents list without dropping the current article" do
    page = repository.page("overview", query: "Kramdown")

    titles = page.groups.flat_map { |group| group.entries.map(&:title) }
    expect(titles).to include("Developer reference")
    expect(titles).not_to include("Dashboard")
    expect(page.title).to eq("Developer reference")
  end

  it "builds topic cards for every non-home page without using the contents query" do
    groups = repository.hub_groups
    topics = groups.flat_map(&:entries)

    expect(groups.map(&:key)).to eq(%w[orientation access builders runtime modules operations])
    expect(topics.map(&:slug)).to eq(DeveloperDocs::Catalog.slugs - ["overview"])
    expect(topics).to all(be_a(described_class::Topic))
    expect(topics.map(&:path)).to all(match(%r{\A/81721200/admin/maintenance/platform/developer_docs/[a-z-]+\z}))
    expect(topics.map(&:title)).to all(be_present)
    expect(topics.map(&:summary)).to all(be_present)
    expect(repository.page("overview", query: "rspec-developer-docs-no-match-7d24f083bc934ea6").groups).to be_empty
    expect(repository.hub_groups.flat_map { |group| group.entries.map(&:slug) }).to include("system-map")
  end

  it "returns nil for an unknown slug" do
    expect(repository.page("not-a-page")).to be_nil
  end

  it "renders the Chinese overview" do
    page = described_class.new(customer_id: "81721200", locale: :"zh-CN").page("overview")

    expect(page.title).to eq("开发文档")
    expect(page.headings.map { |heading| heading[:text] }).to include("概要", "流程", "实现", "需要特别注意", "关键代码")
    expect(page.search_path).to eq("/81721200/admin/maintenance/platform/developer_docs/overview")
    expect(page.next_page.path).to eq("/81721200/admin/maintenance/platform/developer_docs/system-map")
    expect(page.groups.flat_map(&:entries).map(&:path)).to all(match(%r{\A/81721200/admin/maintenance/platform/developer_docs/[a-z-]+\z}))
    expect(page.html).not_to include("?locale=")
  end

  it "publishes every catalog page in both locales with the required sections" do
    DeveloperDocs::Catalog::LOCALES.each do |locale|
      repo = described_class.new(customer_id: "81721200", locale: locale)
      DeveloperDocs::Catalog.slugs.each do |slug|
        page = repo.page(slug)
        expect(page).not_to be_nil, "missing #{locale}/#{slug}.md"
        expect(page.title).to be_present
        expect(page.summary).to be_present
        headings = page.headings.map { |heading| heading[:text] }
        expect(headings).to include(*DeveloperDocs::Catalog::REQUIRED_HEADINGS.fetch(locale))
        expect(page.html).not_to include("<script")
      end
    end
  end

  it "publishes the customer domain attribute beside customers with localized cross-links" do
    DeveloperDocs::Catalog::LOCALES.each do |locale|
      repo = described_class.new(customer_id: "81721200", locale: locale)
      page = repo.page("custom-domains")
      expect(page).to be_present
      expect(page.previous_page.title).to eq(repo.page("customers").title)
      expect(page.html).to include("/81721200/admin/maintenance/platform/developer_docs/page-shortcuts")
      expect(page.html).to include("customers.domain", "CustomDomains::CnameVerifier")
      expect(page.html).not_to include("CustomDomains::Activities::Save", "domain-form")
    end
  end

  context "with navigation sources" do
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }

    def write_navigation_source(slug, locale: "en", title: "Reference #{slug}", summary: "Reference task", body: "## Summary\n\nShared instructions.")
      path = @content_root.join(locale, "#{slug}.md")
      File.write(path, "---\ntitle: #{title}\nsummary: #{summary}\n---\n#{body}\n")
      path
    end

    def navigation_repository(**options)
      described_class.new(customer_id: "81721200", locale: :en, content_root: @content_root, **options)
    end

    around do |example|
      Dir.mktmpdir("reference-navigation", Rails.root.join("tmp")) do |directory|
        @content_root = Pathname.new(directory)
        %w[en zh-CN].each { |locale| @content_root.join(locale).mkpath }
        example.run
      end
    end

    before do
      allow(Rails).to receive(:cache).and_return(cache)
      write_navigation_source("overview", title: "Reference home")
      write_navigation_source("system-map", title: "Workspace map", summary: "Unique architecture")
      write_navigation_source("dashboard", title: "Dashboard metrics")
      write_navigation_source("tenancy-and-roles", title: "Access rules", body: "## Summary\n\nUnique isolation.")
    end

    it "keeps the complete owning group and catalog neighbors when only another group matches" do
      unfiltered = navigation_repository.page("system-map")
      page = navigation_repository.page("system-map", query: "  ISOLATION  ")

      expect(page.query).to eq("ISOLATION")
      expect(page.groups.map(&:key)).to eq(["access"])
      expect(page.groups.flat_map(&:entries).map(&:slug)).to eq(["tenancy-and-roles"])
      expect(page.groups.flat_map(&:entries).select(&:active)).to be_empty
      expect(page.current_group).to eq(unfiltered.current_group)
      expect(page.current_group.key).to eq("orientation")
      expect(page.current_group.entries.map(&:slug)).to eq(%w[overview system-map dashboard])
      expect(page.current_group.entries.select(&:active).map(&:slug)).to eq(["system-map"])
      expect(page.previous_page).to eq(unfiltered.previous_page)
      expect(page.next_page).to eq(unfiltered.next_page)
      expect(page.previous_page.to_h).to eq(slug: "overview", title: "Reference home",
                                          path: "/81721200/admin/maintenance/platform/developer_docs/overview")
      expect(page.next_page.to_h).to eq(slug: "dashboard", title: "Dashboard metrics",
                                      path: "/81721200/admin/maintenance/platform/developer_docs/dashboard")
      expect(page.html).to eq(unfiltered.html)
    end

    {
      "mEtRiCs" => "dashboard",
      "architecture" => "system-map",
      "isolation" => "tenancy-and-roles"
    }.each do |query, slug|
      it "matches source title, summary, or body for #{query.inspect} without adding context as a result" do
        page = navigation_repository.page("overview", query: query)

        expect(page.groups.flat_map(&:entries).map(&:slug)).to eq([slug])
        expect(page.current_group.entries.map(&:slug)).to eq(%w[overview system-map dashboard])
      end
    end

    it "returns genuine empty results while retaining current context and neighbors" do
      unfiltered = navigation_repository.page("system-map")
      page = navigation_repository.page("system-map", query: "no matching reference")

      expect(page.groups).to be_empty
      expect(page.current_group).to eq(unfiltered.current_group)
      expect(page.previous_page).to eq(unfiltered.previous_page)
      expect(page.next_page).to eq(unfiltered.next_page)
    end

    [nil, "", " \t\n "].each do |query|
      it "treats #{query.inspect} as an unapplied query and retains all available groups" do
        page = navigation_repository.page("system-map", query: query)

        expect(page.query).to eq("")
        expect(page.groups.map(&:key)).to eq(%w[orientation access])
        expect(page.groups.flat_map(&:entries).map(&:slug)).to eq(%w[overview system-map dashboard tenancy-and-roles])
        expect(page.current_group).to eq(page.groups.first)
      end
    end

    it "matches using the trimmed first eighty characters of the query" do
      write_navigation_source("dashboard", body: "## Summary\n\n#{'x' * 80}")

      page = navigation_repository.page("system-map", query: "  #{'x' * 100}  ")

      expect(page.query).to eq("x" * 80)
      expect(page.groups.flat_map(&:entries).map(&:slug)).to eq(["dashboard"])
    end

    it "omits an unavailable sibling from current context and skips it in reading order" do
      File.delete(@content_root.join("en/dashboard.md"))

      page = navigation_repository.page("system-map", query: "isolation")

      expect(page.current_group.entries.map(&:slug)).to eq(%w[overview system-map])
      expect(page.current_group.entries.select(&:active).map(&:slug)).to eq(["system-map"])
      expect(page.next_page.slug).to eq("tenancy-and-roles")
      expect(page.groups.flat_map(&:entries).map(&:slug)).to eq(["tenancy-and-roles"])
    end

    it "preserves navigation route options while removing both query key forms" do
      route_options = { q: "symbol query", "q" => "string query", "locale" => "zh-CN", anchor: "summary" }
      page = navigation_repository(route_options: route_options).page("system-map", query: "isolation")
      paths = page.groups.flat_map(&:entries).map(&:path) + page.current_group.entries.map(&:path) +
              [page.previous_page.path, page.next_page.path, page.search_path]

      expect(paths).to all(end_with("?locale=zh-CN#summary"))
      paths.each { |path| expect(path).not_to include("q=") }
      expect(route_options).to eq(q: "symbol query", "q" => "string query", "locale" => "zh-CN", anchor: "summary")
      expect(navigation_repository.page("system-map", search_path: "/supplied/search").search_path).to eq("/supplied/search")
    end

    it "uses localized metadata with English fallback and query-free developer destinations by default" do
      write_navigation_source("system-map", locale: "zh-CN", title: "系统地图", summary: "独有架构")

      page = navigation_repository(locale: :"zh-CN").page("system-map", query: "隔离")

      expect(page.groups).to be_empty
      expect(page.current_group.entries.map(&:title)).to eq(["Reference home", "系统地图", "Dashboard metrics"])
      expect(page.current_group.entries.map(&:path)).to all(match(%r{\A/81721200/admin/maintenance/platform/developer_docs/[a-z-]+\z}))
      expect(page.previous_page.title).to eq("Reference home")
      expect(page.next_page.title).to eq("Dashboard metrics")
      expect(navigation_repository(locale: :"zh-CN").page("overview", query: "独有").groups.flat_map(&:entries).map(&:slug))
        .to eq(["system-map"])
    end

    it "renders only the requested article and reuses loaded source metadata for context and results" do
      %w[overview system-map dashboard tenancy-and-roles].each do |slug|
        expect(File).to receive(:read).with(@content_root.join("en", "#{slug}.md"), encoding: "UTF-8").once.and_call_original
      end
      expect(DeveloperDocs::Renderer).to receive(:call).once.and_call_original

      page = navigation_repository.page("system-map", query: "isolation")

      expect(page.title).to eq("Workspace map")
      expect(page.current_group.entries.map(&:slug)).to eq(%w[overview system-map dashboard])
      expect(page.groups.flat_map(&:entries).map(&:slug)).to eq(["tenancy-and-roles"])
    end

    it "reads fresh context and neighbor metadata on the next request even when article HTML is cached" do
      original = navigation_repository.page("system-map")
      timestamp = File.mtime(@content_root.join("en/system-map.md"))
      write_navigation_source("system-map", title: "Updated map", summary: "Revised overview")
      File.utime(timestamp, timestamp, @content_root.join("en/system-map.md"))
      write_navigation_source("dashboard", title: "Fresh dashboard")
      expect(DeveloperDocs::Renderer).not_to receive(:call)

      page = navigation_repository.page("system-map", query: "fresh")

      expect(page.html).to eq(original.html)
      expect(page.title).to eq("Updated map")
      expect(page.summary).to eq("Revised overview")
      expect(page.current_group.entries.map(&:title)).to eq(["Reference home", "Updated map", "Fresh dashboard"])
      expect(page.groups.flat_map(&:entries).map(&:title)).to eq(["Fresh dashboard"])
      expect(page.next_page.title).to eq("Fresh dashboard")
    end
  end

  context "with screenshot content" do
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }
    let(:source) { "/help/docs/screenshots/en/records-list.png" }
    let(:image_labels) { { full_size: "View full size", open: "View full size: %{caption}" } }

    def screenshot_repository(**options)
      described_class.new(customer_id: "81721200", locale: :en, content_root: @content_root, **options)
    end

    around do |example|
      Dir.mktmpdir("reference-screenshots", Rails.root.join("tmp")) do |directory|
        @content_root = Pathname.new(directory)
        @content_root.join("en").mkpath
        File.write(@content_root.join("en/overview.md"), <<~MD)
          ---
          title: Screenshot policy
          summary: Policy isolation
          ---
          ## Summary

          ![Record controls](#{source} "Find a record.")
        MD
        example.run
      end
    end

    before do
      allow(Rails).to receive(:cache).and_return(cache)
    end

    it "strips images by default and requires a deliberate root and localized labels to render them" do
      reference = screenshot_repository.page("overview")
      enabled = screenshot_repository(screenshot_root: "/help/docs/screenshots", screenshot_labels: image_labels).page("overview")

      expect(reference.html).not_to include("<img", "<figure", "Record controls", "View full size")
      expect(enabled.html).to include("<figure", %(src="#{source}"), "View full size: Find a record.")
      expect(DeveloperDocs::Renderer).not_to receive(:call)
      expect(screenshot_repository.page("overview").html).to eq(reference.html)
      expect(screenshot_repository(screenshot_root: "/help/docs/screenshots", screenshot_labels: image_labels).page("overview").html)
        .to eq(enabled.html)
    end

    it "cannot reuse opt-in HTML when the next caller uses the reference defaults" do
      screenshot_repository(screenshot_root: "/help/docs/screenshots", screenshot_labels: image_labels).page("overview")

      reference = screenshot_repository.page("overview")

      expect(reference.html).not_to include("<figure", "<img", source)
    end

    it "separates cached fragments when the renderer version changes" do
      screenshot_repository.page("overview")
      stub_const("DeveloperDocs::Renderer::CACHE_VERSION", "documentation/test-next-version")
      expect(DeveloperDocs::Renderer).to receive(:call).and_call_original

      screenshot_repository.page("overview")
    end

    it "separates cached fragments when the screenshot policy version changes" do
      options = { screenshot_root: "/help/docs/screenshots", screenshot_labels: image_labels }
      screenshot_repository(**options).page("overview")
      stub_const("DeveloperDocs::Renderer::SCREENSHOT_POLICY_VERSION", "screenshots/test-next-policy")
      expect(DeveloperDocs::Renderer).to receive(:call).and_call_original

      screenshot_repository(**options).page("overview")
    end
  end
end
