# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Platform::DeveloperDocs", type: :request do
  let(:platform_owner) { find_or_create_platform_owner }
  let(:platform_cid) { ensure_platform_customer.id }
  let(:guard_path) { admin_maintenance_platform_developer_docs_path(platform_cid) }

  it_behaves_like "a platform-owner-guarded GET"

  describe "platform owner" do
    before { sign_in platform_owner }

    it "renders the overview with in-page heading links" do
      get guard_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Developer reference")
      expect(response.body).to include("Browse by topic")
      expect(response.body).to include('id="developer-doc-guides-title"')
      expect(response.body).to include('href="#summary"')
      document = Nokogiri::HTML(response.body)
      expect(document.at_css(".docs-page")).to be_present
      expect(document.css("h1").map(&:text)).to eq(["Developer reference"])
      expect(document.at_css("[data-docs-reader-center] > header h1").text).to eq("Developer reference")
      expect(document.css("nav[aria-label='On this page']")).to be_empty
      expect(response.body).to include(admin_maintenance_platform_developer_doc_path(platform_cid, "system-map"))
    end

    it "omits topic cards on non-home pages and keeps a path back to the index" do
      get admin_maintenance_platform_developer_doc_path(platform_cid, "system-map")

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('id="developer-doc-guides-title"')
      expect(response.body).not_to include("Reference home")
      expect(response.body).to include("More in this section")
      expect(Nokogiri::HTML(response.body).css("nav[aria-label='On this page']")).not_to be_empty
    end

    it "renders a single page and a Chinese locale" do
      get admin_maintenance_platform_developer_doc_path(platform_cid, "system-map"), params: { locale: "zh-CN" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("系统地图")
      expect(response.body).to include("概要")
      document = Nokogiri::HTML(response.body)
      expect(document.css("[data-controller~='developer-docs-nav'] input[name='locale']").map { |input| input["value"] }).to eq(["zh-CN", "zh-CN"])
      search_path = URI.parse(admin_maintenance_platform_developer_doc_path(platform_cid, "system-map")).path
      expect(document.css("form input[name='q']").map { |input| URI.parse(input.ancestors("form").first["action"]).path })
        .to eq([search_path, search_path])
      expect(document.css("a[href*='/admin/maintenance/platform/developer_docs/']").map { |link| link["href"] })
        .to all(satisfy { |href| Addressable::URI.parse(href).query_values == { "locale" => "zh-CN" } })
    end

    it "filters the contents from the search query" do
      get guard_path, params: { q: "Kramdown" }

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      contents = document.css("[data-docs-nav-list] li > a[href]").map { |link| link["href"] }.uniq
      expect(contents).to include(admin_maintenance_platform_developer_doc_path(platform_cid, "overview", locale: "en"))
      expect(contents).not_to include(admin_maintenance_platform_developer_doc_path(platform_cid, "dashboard", locale: "en"))
      expect(document.at_css("#developer-doc-guides-title")).to be_present
    end

    it "preserves an explicit Chinese locale through a topic link and a search form with an English user preference" do
      platform_owner.update!(locale: "en")
      get guard_path, params: { locale: "zh-CN" }
      document = Nokogiri::HTML(response.body)
      topic = document.at_css("section[aria-labelledby='developer-doc-guides-title']").css("a[href]").find do |link|
        link["href"].include?("/system-map")
      end

      get topic["href"]
      expect(response.body).to include("系统地图")
      form = Nokogiri::HTML(response.body).at_css("[data-controller~='developer-docs-nav'] form")
      locale = form.at_css("input[name='locale']")["value"]

      get form["action"], params: { q: "no-reference-matches-this-qa-query", locale: locale }

      expect(response.body).to include("系统地图")
      expect(locale).to eq("zh-CN")
      expect(platform_owner.reload.locale).to eq("en")
    end

    [nil, "system-map"].each do |slug|
      it "clears an empty Chinese search on #{slug || 'index'} without falling back to the English user preference" do
        platform_owner.update!(locale: "en")
        path = slug ? admin_maintenance_platform_developer_doc_path(platform_cid, slug) : guard_path
        get path, params: { locale: "zh-CN", q: "no-reference-matches-this-qa-query" }
        expect(response).to have_http_status(:ok)
        document = Nokogiri::HTML(response.body)
        clear_links = document.css(".docs-page a[href]").select do |link|
          link.text.strip == I18n.t("developer_docs.search_clear", locale: "zh-CN")
        end
        expect(clear_links.size).to be >= 2
        clear_links.each do |link|
          url = Addressable::URI.parse(link["href"])
          expect(url.path).to eq(URI.parse(path).path)
          expect(url.query_values).to eq("locale" => "zh-CN")
        end

        get clear_links.first["href"]
        expect(response).to have_http_status(:ok)
        cleared = Nokogiri::HTML(response.body)
        expect(cleared.at_css("html")["lang"]).to eq("zh-CN")
        expect(cleared.css(".docs-page input[name='q']").map { |input| input["value"] }).to eq(["", ""])
        expect(platform_owner.reload.locale).to eq("en")
      end
    end

    %w[en zh-CN].each do |locale|
      [nil, "overview"].each do |slug|
        [nil, "Kramdown", "no-reference-matches-this-qa-query"].each do |query|
          it "keeps the complete #{locale} topic directory on #{slug || 'index'} with query #{query.inspect}" do
            path = slug ? admin_maintenance_platform_developer_doc_path(platform_cid, slug) : guard_path
            get path, params: { locale: locale, q: query }

            expect(response).to have_http_status(:ok)
            document = Nokogiri::HTML(response.body)
            directory = document.at_css("section[aria-labelledby='developer-doc-guides-title']")
            slugs = DeveloperDocs::Catalog.slugs - [DeveloperDocs::Catalog::HOME_SLUG]
            expect(directory.css("a[href]").map { |link| link['href'] }).to eq(slugs.map do |topic|
              admin_maintenance_platform_developer_doc_path(platform_cid, topic, locale: locale)
            end)
            expect(directory.css(".card").size).to eq(DeveloperDocs::Catalog.groups.size)
            expect(document.css("h1").size).to eq(1)
            expect(document.at_css("[data-docs-reader-center] > header h1")).to be_present
            expect(document.at_css(".developer-doc").text).to include(locale == "en" ? "Summary" : "概要")
            expect(document.css("nav[aria-label='#{I18n.t('developer_docs.on_this_page', locale: locale)}']")).to be_empty
            if query == "no-reference-matches-this-qa-query"
              expect(document.css("[data-docs-nav-list] li > a")).to be_empty
              expect(response.body).to include(I18n.t("developer_docs.search_empty", locale: locale))
            end
          end
        end
      end
    end

    it "returns not found for an unknown slug" do
      get admin_maintenance_platform_developer_doc_path(platform_cid, "not-a-page")

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include(I18n.t("developer_docs.missing_title"))
    end

    %w[en zh-CN].each do |locale|
      it "retains the unfiltered #{locale} article context and locale-only neighbors during search" do
        path = admin_maintenance_platform_developer_doc_path(platform_cid, "system-map")
        get path, params: { locale: locale }
        original = Nokogiri::HTML(response.body)
        title = original.at_css("h1").text
        section_label = I18n.t("developer_docs.more_in_section", locale: locale)
        siblings = original.css("nav[aria-label='#{section_label}'] a").map { |link| link["href"] }
        neighbors = original.css("[data-docs-footer-sequence] a").map { |link| link["href"] }
        group_path = "#{admin_maintenance_platform_developer_docs_path(platform_cid, locale: locale)}#developer-doc-guide-group-orientation"
        localized_path = admin_maintenance_platform_developer_doc_path(platform_cid, "system-map", locale: locale)

        ["Kramdown", "no-reference-matches-this-qa-query", title].each do |query|
          get path, params: { locale: locale, q: query }
          expect(response).to have_http_status(:ok)
          doc = Nokogiri::HTML(response.body)
          expect(doc.css("h1").map(&:text)).to eq([title])
          expect(doc.at_css("[data-docs-reader-center] > header a[href='#{group_path}']")).not_to be_nil
          expect(doc.css("nav[aria-label='#{section_label}'] a").map { |link| link["href"] }).to eq(siblings)
          expect(doc.css("[data-docs-footer-sequence] a").map { |link| link["href"] }).to eq(neighbors)
          expect(neighbors).to all(satisfy { |href| Addressable::URI.parse(href).query_values == { "locale" => locale } })
          %w[desktop mobile].each do |surface|
            header = doc.at_css("[data-docs-nav-header='#{surface}']")
            expect(header.css("a[aria-current='page']").size).to eq(1)
            expect(header.at_css("a[aria-current='page']")["href"]).to eq(localized_path)
            expect(header.at_css("a[href='#{group_path}']")).not_to be_nil
            expect(doc.css("[data-docs-nav-list='#{surface}'] a[aria-current], [data-docs-nav-list='#{surface}'] [data-docs-current-guide]")).to be_empty
          end
          results = doc.css("[data-docs-nav-list='desktop'] li > a").map { |link| link["href"] }
          if query == title
            expect(results).to include(localized_path)
          elsif query == "no-reference-matches-this-qa-query"
            expect(results).to be_empty
          else
            expect(results).not_to be_empty
            expect(results).not_to include(localized_path)
          end
        end
      end
    end
  end
end
