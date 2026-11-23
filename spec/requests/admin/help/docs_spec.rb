# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Help::Docs", type: :request do
  include_context "admin records"

  let(:member) { create(:user, :member, customer: customer) }
  let(:other_admin) { create(:user, :admin, customer: create(:customer)) }
  let(:platform_owner) { find_or_create_platform_owner }

  def document
    Nokogiri::HTML(response.body)
  end

  def contents_links(locale = :en)
    document.css("[data-docs-nav-list] li > a[href]").map { |link| link["href"] }.uniq
  end

  def search_forms
    document.css("[data-controller~='developer-docs-nav'] form")
  end

  def expect_private_response
    expect(response.headers.fetch("Cache-Control").split(/,\s*/)).to contain_exactly("private", "no-store")
  end

  def guide_metadata(slug, locale)
    source = File.read(Rails.root.join("doc/customer", locale.to_s, "#{slug}.md"), encoding: "UTF-8")
    YAML.safe_load(source.match(/\A---\r?\n(.*?)\r?\n---\r?\n/m)[1], permitted_classes: [], aliases: false)
  end

  def home_cards
    document.css("section[aria-labelledby='customer-doc-guides-title'] a[href]")
  end

  def expect_home_cards(locale)
    slugs = CustomerDocs::Catalog.slugs - [CustomerDocs::Catalog::HOME_SLUG]
    cards = home_cards

    expect(cards.size).to eq(12)
    expect(cards.map { |card| card["href"] }).to eq(slugs.map do |slug|
      admin_help_doc_path(customer.id, slug, locale: locale)
    end)
    expect(document.at_css("#customer-doc-guides-title").text.strip).to eq(I18n.t("customer_docs.home.guides_title", locale: locale))
    cards.zip(slugs).each do |card, slug|
      metadata = guide_metadata(slug, locale)
      expect(card.at_css("h4").text).to eq(metadata.fetch("title"))
      expect(card.at_css("p").text).to eq(metadata.fetch("summary"))
      expect(card["target"]).to be_nil
      expect(Rack::Utils.parse_query(URI.parse(card["href"]).query)).to eq("locale" => locale.to_s)
    end
  end

  def article_guide_links(locale = :en)
    document.css(".customer-doc a[href^='/']").filter_map do |link|
      href = link["href"]
      if (figure = link.ancestors("figure").first)
        expect(href).to match(%r{\A/help/docs/screenshots/#{Regexp.escape(locale.to_s)}/[a-z0-9]+(?:-[a-z0-9]+)*\.png\z})
        expect(href).to eq(figure.at_css("img")["src"])
        expect(link["target"]).to be_nil
        next
      end

      uri = URI.parse(href)
      slug = uri.path.split("/").last
      expect(CustomerDocs::Catalog.slugs).to include(slug)
      expect(uri.path).to eq(admin_help_doc_path(customer.id, slug))
      expect(Rack::Utils.parse_query(uri.query)).to eq("locale" => locale.to_s)
      href
    end
  end

  { index: nil, overview: "overview", article: "getting-started" }.each do |endpoint, slug|
    describe endpoint.to_s do
      let(:path) do
        slug ? admin_help_doc_path(customer.id, slug) : admin_help_docs_path(customer.id)
      end

      %i[get head].each do |verb|
        describe verb.to_s.upcase do
          it "redirects anonymous HTML requests to sign in" do
            public_send(verb, path)

            expect(response).to have_http_status(:found)
            expect(response).to redirect_to(new_user_session_path)
            expect(response.body).not_to include("Choose your next workspace task", "Get started in your workspace")
            expect(home_cards).to be_empty
          end

          it "requires authentication for anonymous JSON requests" do
            public_send(verb, path, headers: json_headers)

            expect(response).to have_http_status(:unauthorized)
            expect(response.body).not_to include("Choose your next workspace task", "Get started in your workspace")
          end

          it "redirects members to their own member dashboard for HTML" do
            sign_in member
            public_send(verb, path)

            expect(response).to have_http_status(:found)
            expect(response).to redirect_to(member_dashboard_path(customer.id))
            expect(response.body).not_to include("Choose your next workspace task", "Get started in your workspace")
            expect(home_cards).to be_empty
          end

          it "forbids members requesting JSON" do
            sign_in member
            public_send(verb, path, headers: json_headers)

            expect(response).to have_http_status(:forbidden)
            if verb == :get
              expect(response.parsed_body).to eq("error" => "access_denied")
            else
              expect(response.body).to be_empty
            end
          end

          it "redirects cross-tenant admins to their own admin landing page for HTML" do
            sign_in other_admin
            public_send(verb, path)

            expect(response).to have_http_status(:found)
            expect(response).to redirect_to(admin_assistant_path(other_admin.customer_id))
            expect(response.body).not_to include("Choose your next workspace task", "Get started in your workspace")
            expect(home_cards).to be_empty
          end

          it "forbids cross-tenant admins requesting JSON" do
            sign_in other_admin
            public_send(verb, path, headers: json_headers)

            expect(response).to have_http_status(:forbidden)
            if verb == :get
              expect(response.parsed_body).to eq("error" => "access_denied")
            else
              expect(response.body).to be_empty
            end
          end
        end
      end

      context "own-tenant admin" do
        before { sign_in admin }

        {
          en: {
            index: "Choose your next workspace task", overview: "Choose your next workspace task", article: "Get started in your workspace",
            body: "These guides are for customer administrators.",
            article_body: "Use the email address associated with your administrator account."
          },
          "zh-CN": {
            index: "选择下一项工作区任务", overview: "选择下一项工作区任务", article: "开始使用工作区",
            body: "本指南面向客户管理员。",
            article_body: "请使用管理员账户关联的邮箱。"
          }
        }.each do |locale, content|
          it "renders real #{locale} content, localized reader labels, and the internal Help link" do
            get path, params: { locale: locale }

            expect(response).to have_http_status(:ok)
            expect_private_response
            expect(document.at_css("html")["lang"]).to eq(locale.to_s)
            expect(document.css("h1").map(&:text)).to eq([content.fetch(endpoint)])
            expect(document.at_css("[data-docs-reader-center] > header h1").text).to eq(content.fetch(endpoint))
            expect(document.at_css(".docs-page")).not_to be_nil
            expect(document.at_css(".customer-doc").text).to include(content.fetch(endpoint == :article ? :article_body : :body))
            toc = document.css("nav[aria-label='#{I18n.t("customer_docs.on_this_page", locale: locale)}']")
            if endpoint == :article
              expect(toc).not_to be_empty
            else
              expect(toc).to be_empty
            end
            expect(response.body).to include(I18n.t("customer_docs.search_placeholder", locale: locale))
            expect(response.body).not_to match(/translation missing/i)

            help_link = document.at_css("a[role='menuitem'][href='#{admin_help_docs_path(customer.id, locale: locale)}']")
            expect(help_link).not_to be_nil
            expect(help_link.text).to include(I18n.t("chrome.help_menu.docs.label", locale: locale))
            expect(help_link["target"]).to be_nil
            expect(response.body).not_to include("https://docs.anysys.com")

            expected_paths = CustomerDocs::Catalog.slugs.map { |guide| admin_help_doc_path(customer.id, guide, locale: locale) }
            expect(contents_links(locale)).to eq(expected_paths)
            search_path = slug ? admin_help_doc_path(customer.id, slug, locale: locale) : admin_help_docs_path(customer.id, locale: locale)
            expect(document.css("form input[name='q']").map { |input| input.ancestors("form").first["action"] }).to eq([search_path, search_path])
            expect(search_forms.css("input[type='hidden'][name='locale']").map { |input| input["value"] }).to eq([locale.to_s, locale.to_s])
            if endpoint == :article
              expect(document.at_css("a[href='#{admin_help_docs_path(customer.id, locale: locale)}']:not([role='menuitem'])")).not_to be_nil
            end
          end
        end

        it "highlights no top-menu tab and renders no sidebar, since Help lives in the topbar menu" do
          get path, params: { locale: :en }

          expect(document.css("nav[aria-label='Dashboard menu'] a[aria-current='page']")).to be_empty
          expect(document.css("[data-menu-item][aria-current='page']")).to be_empty
          expect(document.at_css("[data-controller~='sidebar-collapsible']")).to be_nil
        end

        it "allows HEAD with the same private cache policy and an empty body" do
          head path

          expect(response).to have_http_status(:ok)
          expect_private_response
          expect(response.body).to be_empty
        end
      end

      context "platform owner in another tenant's workspace" do
        before { sign_in platform_owner }

        it "renders customer guides and navigation for the URL tenant" do
          get path, params: { locale: "en" }

          expect(response).to have_http_status(:ok)
          expect_private_response
          expect(document.at_css(".customer-doc")).not_to be_nil
          expect(contents_links).to include(admin_help_doc_path(customer.id, "getting-started", locale: :en))
          expect(contents_links).to all(start_with("/#{customer.id}/admin/help/docs/"))
          expect(document.at_css("a[role='menuitem'][href='#{admin_help_docs_path(customer.id, locale: :en)}']")).not_to be_nil
          article_links = article_guide_links
          expect(article_links).not_to be_empty
          expect(article_links).to all(start_with("/#{customer.id}/admin/help/docs/"))
          expect(article_links).not_to include(a_string_including("/#{platform_owner.customer_id}/"))
          expect_home_cards(:en) unless endpoint == :article
        end
      end

      context "admin of the platform customer without the owner role" do
        let(:customer) { ensure_platform_customer }

        before { sign_in admin }

        it "can read the customer guide" do
          expect(admin).to be_admin_or_owner
          expect(admin).not_to be_platform_owner

          get path, params: { locale: "en" }

          expect(response).to have_http_status(:ok)
          expect_private_response
          expect(document.at_css(".customer-doc")).not_to be_nil
          expect(contents_links).to include(admin_help_doc_path(customer.id, "getting-started", locale: :en))
        end
      end
    end
  end

  describe "homepage task cards" do
    before { sign_in admin }

    { index: nil, overview: "overview" }.each do |endpoint, slug|
      context "on the #{endpoint}" do
        let(:path) { slug ? admin_help_doc_path(customer.id, slug) : admin_help_docs_path(customer.id) }

        %w[en zh-CN].each do |locale|
          it "renders twelve #{locale} metadata cards using one repository and opens a localized guide" do
            allow(CustomerDocs::Repository).to receive(:new).and_call_original

            get path, params: { locale: locale }

            expect(response).to have_http_status(:ok)
            expect_private_response
            expect_home_cards(locale)
            expect(article_guide_links(locale)).not_to be_empty
            expect(CustomerDocs::Repository).to have_received(:new).once

            card = home_cards.find { |link| link["href"] == admin_help_doc_path(customer.id, "forms", locale: locale) }
            get card["href"]

            expect(response).to have_http_status(:ok)
            expect(document.at_css("html")["lang"]).to eq(locale)
            expect(document.css("h1").map(&:text)).to include(guide_metadata("forms", locale).fetch("title"))
            expect(home_cards).to be_empty
            expect(CustomerDocs::Repository).to have_received(:new).twice
          end
        end

        [nil, "unsupported"].each do |requested_locale|
          it "uses the stored Chinese locale for cards when the requested locale is #{requested_locale.inspect}" do
            admin.update!(locale: "zh-CN")
            get path, params: { locale: requested_locale }

            expect(response).to have_http_status(:ok)
            expect(document.at_css("html")["lang"]).to eq("zh-CN")
            expect_home_cards("zh-CN")
          end
        end
      end
    end

    %w[en zh-CN].each do |locale|
      it "keeps cards absent from every non-overview #{locale} guide" do
        (CustomerDocs::Catalog.slugs - [CustomerDocs::Catalog::HOME_SLUG]).each do |slug|
          get admin_help_doc_path(customer.id, slug, locale: locale)

          expect(response).to have_http_status(:ok)
          expect(home_cards).to be_empty
          expect(document.at_css("#customer-doc-guides-title")).to be_nil
          expect(article_guide_links(locale)).not_to be_empty
        end
      end

      it "uses the URL tenant for #{locale} cards when the platform owner visits another workspace" do
        sign_out admin
        sign_in platform_owner

        get admin_help_docs_path(customer.id, locale: locale)

        expect(response).to have_http_status(:ok)
        expect(customer.id).not_to eq(platform_owner.customer_id)
        expect_home_cards(locale)
        expect(home_cards.map { |card| card["href"] }).not_to include(a_string_including("/#{platform_owner.customer_id}/"))
      end
    end
  end

  describe "localized screenshot figures" do
    before { sign_in admin }

    {
      "getting-started" => "workspace-help",
      "records" => "records-list",
      "forms" => "forms-publishing",
      "websites" => "website-publishing",
      "email" => "email-audience",
      "payments" => "payment-settings"
    }.each do |slug, basename|
      %w[en zh-CN].each do |locale|
        it "renders #{slug}'s #{locale} caption and native static links without locale or search queries" do
          source_path = "/help/docs/screenshots/#{locale}/#{basename}.png"
          markdown = File.read(Rails.root.join("doc/customer", locale, "#{slug}.md"), encoding: "UTF-8")
          authored_image = markdown.match(/!\[([^\]]+)\]\(#{Regexp.escape(source_path)} "([^"]+)"\)/)
          expect(authored_image).not_to be_nil

          get admin_help_doc_path(customer.id, slug), params: { locale: locale, q: "no-guide-matches-this-qa-query" }

          expect(response).to have_http_status(:ok)
          expect_private_response
          expect(contents_links(locale)).to be_empty
          figures = document.css(".customer-doc figure")
          expect(figures.size).to eq(1)
          figure = figures.first
          image = figure.at_css("a > img")
          expect(image["src"]).to eq(source_path)
          expect(image["alt"]).to eq(authored_image[1])
          expect(image["loading"]).to eq("lazy")
          expect(image["decoding"]).to eq("async")
          expect(figure.at_css("figcaption > span").text).to eq(authored_image[2])
          expect(figure.at_css("figcaption > a").text).to eq(I18n.t("customer_docs.screenshots.full_size", locale: locale))
          expect(figure.at_css("a[aria-label]")["aria-label"]).to eq(I18n.t("customer_docs.screenshots.open", locale: locale, caption: authored_image[2]))
          links = figure.css("a[href]")
          expect(links.map { |link| link["href"] }).to eq([source_path, source_path])
          links.each do |link|
            uri = URI.parse(link["href"])
            expect(uri.query).to be_nil
            expect(uri.fragment).to be_nil
            expect(link["target"]).to be_nil
          end
          expect(article_guide_links(locale)).not_to be_empty
        end
      end
    end
  end

  describe "article navigation and search" do
    before { sign_in admin }

    let(:path) { admin_help_doc_path(customer.id, "getting-started") }

    [nil, "unsupported"].each do |requested_locale|
      it "preserves the effective stored locale when the request locale is #{requested_locale.inspect}" do
        admin.update!(locale: "zh-CN")
        get path, params: { locale: requested_locale }

        expect(response).to have_http_status(:ok)
        expect(document.at_css("html")["lang"]).to eq("zh-CN")
        expect(contents_links(:"zh-CN")).to eq(CustomerDocs::Catalog.slugs.map do |guide|
          admin_help_doc_path(customer.id, guide, locale: :"zh-CN")
        end)
        expect(search_forms.css("input[name='locale']").map { |input| input["value"] }).to eq(%w[zh-CN zh-CN])
        expect(search_forms.map { |form| form["action"] }).to include(
          admin_help_doc_path(customer.id, "getting-started", locale: :"zh-CN")
        )
      end
    end

    it "keeps related guides, active contents, and previous/next navigation in the URL tenant" do
      get path, params: { locale: "en" }

      expect(response).to have_http_status(:ok)
      active = document.css("nav[aria-label='Contents'] a[aria-current='page']")
      expect(active.map { |link| link["href"] }.uniq).to eq([admin_help_doc_path(customer.id, "getting-started", locale: :en)])
      sequence = document.at_css("[data-docs-footer-sequence]")
      expect(sequence.css("a").map { |link| link["href"] }).to eq([
        admin_help_doc_path(customer.id, "overview", locale: :en), admin_help_doc_path(customer.id, "assistant", locale: :en)
      ])
      related = article_guide_links
      expect(related).to include(admin_help_doc_path(customer.id, "users", locale: :en), admin_help_doc_path(customer.id, "support", locale: :en))
      expect(related).to all(start_with("/#{customer.id}/admin/help/docs/"))
      expect(document.at_css("a[href='#steps']")).not_to be_nil
      expect(document.at_css(".customer-doc #steps")).not_to be_nil
    end

    { index: nil, overview: "overview", article: "getting-started" }.each do |endpoint, slug|
      context "on the #{endpoint}" do
        let(:path) { slug ? admin_help_doc_path(customer.id, slug) : admin_help_docs_path(customer.id) }

        it "treats a blank search as the full customer catalog" do
          get path, params: { q: "  ", locale: "en" }

          expect(response).to have_http_status(:ok)
          expect(contents_links).to eq(CustomerDocs::Catalog.slugs.map { |guide| admin_help_doc_path(customer.id, guide, locale: :en) })
          expect(document.css("input[name='q']").map { |input| input["value"] }.uniq).to eq([""])
          expect_home_cards(:en) unless endpoint == :article
        end

        it "filters contents by real article body text without replacing the current article or neighbors" do
          get path, params: { q: "  APPROVED SENDER  ", locale: "en" }

          expect(response).to have_http_status(:ok)
          expect_private_response
          expect(contents_links).to eq([admin_help_doc_path(customer.id, "sms", locale: :en)])
          expect(document.css("input[name='q']").map { |input| input["value"] }.uniq).to eq(["APPROVED SENDER"])
          expect(document.at_css(".customer-doc").text).to include(
            endpoint == :article ? "Use the email address associated with your administrator account." : "These guides are for customer administrators."
          )
          sequence = document.at_css("[data-docs-footer-sequence]")
          expect(sequence.css("a").map { |link| link["href"] }).to include(
            admin_help_doc_path(customer.id, endpoint == :article ? "assistant" : "getting-started", locale: :en)
          )
          clear_link = document.css("[data-docs-nav-header] a").find { |link| link.text.strip == I18n.t("customer_docs.search_clear", locale: :en) }
          expect(clear_link["href"]).to eq(slug ? admin_help_doc_path(customer.id, slug, locale: :en) : admin_help_docs_path(customer.id, locale: :en))
          expect_home_cards(:en) unless endpoint == :article
        end

        it "renders a localized no-results state while retaining the article" do
          get path, params: { q: "no-guide-matches-this-qa-query", locale: "zh-CN" }

          expect(response).to have_http_status(:ok)
          expect_private_response
          expect(contents_links(:"zh-CN")).to be_empty
          expect(response.body).to include(I18n.t("customer_docs.search_empty", locale: :"zh-CN"))
          expect(document.at_css(".customer-doc").text).to include(endpoint == :article ? "请使用管理员账户关联的邮箱。" : "本指南面向客户管理员。")
          expect_home_cards("zh-CN") unless endpoint == :article
        end
      end
    end
  end

  describe "switching language through the global locale switcher" do
    before do
      admin.update!(locale: "en")
      sign_in admin
    end

    it "switches an English article to Chinese and back while retaining its tenant, search, and fragment" do
      path = admin_help_doc_path(customer.id, "getting-started")
      query = "account & profile"
      get path, params: { locale: "en", q: query }
      expect(document.css("h1").map(&:text)).to include("Get started in your workspace")

      {
        "zh-CN" => ["开始使用工作区", "请使用管理员账户关联的邮箱。"],
        "en" => ["Get started in your workspace", "Use the email address associated with your administrator account."]
      }.each do |locale, (title, body)|
        form = document.css("form[action='#{locale_path}']").find do |candidate|
          candidate.at_css("input[name='locale']")&.[]("value") == locale
        end
        expect(form).not_to be_nil
        fields = form.css("input[name]").to_h { |input| [input["name"], input["value"]] }
        referer = "#{request.url}#steps"
        patch form["action"], params: fields, headers: { "HTTP_REFERER" => referer }

        location = URI.parse(response.location)
        expect(location.path).to eq(path)
        expect(location.fragment).to eq("steps")
        expect(Rack::Utils.parse_query(location.query)).to eq("locale" => locale, "q" => query)
        expect(admin.reload.locale).to eq(locale)
        expect(response.cookies["locale"]).to eq(locale)

        follow_redirect!
        expect(response).to have_http_status(:ok)
        expect_private_response
        expect(document.at_css("html")["lang"]).to eq(locale)
        expect(document.css("h1").map(&:text)).to include(title)
        expect(document.at_css(".customer-doc").text).to include(body)
        expect(document.css("input[name='q']").map { |input| input["value"] }).to eq([query, query])
        expect(search_forms.css("input[name='locale']").map { |input| input["value"] }).to eq([locale, locale])
      end
    end

    it "keeps an explicit Chinese article and English preference when a switch requests an unsupported locale" do
      path = admin_help_doc_path(customer.id, "getting-started", locale: "zh-CN", q: "users")
      get path

      patch locale_path, params: { locale: "fr" }, headers: { "HTTP_REFERER" => request.url }

      expect(response).to redirect_to(path)
      expect(admin.reload.locale).to eq("en")
      expect(response.cookies["locale"]).to be_nil
      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(document.at_css("html")["lang"]).to eq("zh-CN")
      expect(document.css("h1").map(&:text)).to include("开始使用工作区")
      expect(document.css("input[name='q']").map { |input| input["value"] }).to eq(%w[users users])
    end
  end

  describe "query-independent article context" do
    before { sign_in admin }

    %w[en zh-CN].each do |locale|
      it "retains #{locale} group, full-title siblings and neighbors through exclusion, no results and current-match searches" do
        path = admin_help_doc_path(customer.id, "forms", locale: locale)
        get path
        full_title = guide_metadata("forms", locale).fetch("title")
        group_path = "#{admin_help_docs_path(customer.id, locale: locale)}#customer-doc-guide-group-content"
        expected_neighbors = %w[records websites].map { |slug| admin_help_doc_path(customer.id, slug, locale: locale) }
        expected_siblings = [admin_help_doc_path(customer.id, "websites", locale: locale)]
        exclusion = locale == "en" ? "approved sender" : "经批准的发送方"

        [exclusion, "no-guide-matches-this-qa-query", full_title].each do |query|
          get path, params: { q: query }

          expect(response).to have_http_status(:ok)
          expect_private_response
          expect(document.css("h1").map(&:text)).to eq([full_title])
          header = document.at_css("[data-docs-reader-center] > header")
          expect(header.at_css("a[href='#{group_path}']").text).to eq(I18n.t("customer_docs.groups.content", locale: locale))
          expect(header.text).to include(I18n.t("customer_docs.nav_labels.forms", locale: locale))
          expect(header.css("a[aria-current]")).to be_empty
          footer = document.at_css("[data-docs-footer-sequence]")
          expect(footer.css("a").map { |link| link["href"] }).to eq(expected_neighbors)
          section = document.at_css("nav[aria-label='#{I18n.t('customer_docs.more_in_section', locale: locale)}']")
          expect(section.css("a").map { |link| link["href"] }).to eq(expected_siblings)
          expect(section.text).to include(guide_metadata("websites", locale).fetch("title"))

          %w[desktop mobile].each do |surface|
            scope = document.at_css(surface == "desktop" ? "aside[data-developer-docs-nav-target='desktop']" : ".docs-page [role='dialog']")
            current = scope.css("a[aria-current='page']")
            expect(current.size).to eq(1)
            expect(current.first["href"]).to eq(path)
            expect(current.first.text).to eq(I18n.t("customer_docs.nav_labels.forms", locale: locale))
            expect(scope.at_css("[data-docs-nav-header] a[aria-current='page']")).to eq(current.first)
            expect(scope.at_css("##{current.first['aria-describedby']}").text).to eq(full_title)
            expect(scope.css("[data-docs-nav-list] a[aria-current], [data-docs-nav-list] [data-docs-current-guide]")).to be_empty
            expect(scope.at_css("[data-docs-nav-header] button[type='submit']").text).to eq(I18n.t("customer_docs.search_submit", locale: locale))
          end
          case query
          when exclusion
            expect(contents_links(locale)).to eq([admin_help_doc_path(customer.id, "sms", locale: locale)])
          when full_title
            expect(contents_links(locale)).to include(path)
          else
            expect(contents_links(locale)).to be_empty
            expect(document.css("[data-docs-nav-list] [role='alert']")).to be_empty
          end
          ids = document.css(".docs-page [id]").map { |node| node["id"] }
          expect(ids.uniq).to eq(ids)
        end

        get group_path
        expect(response).to have_http_status(:ok)
        expect(document.at_css("#customer-doc-guide-group-content")).not_to be_nil
        expect(document.at_css("#customer-doc-guide-group-home")).not_to be_nil
        expect_home_cards(locale)
      end
    end
  end

  describe "Chinese guide browsing with an English account preference" do
    before do
      admin.update!(locale: "en")
      sign_in admin
    end

    def expect_chinese_guide(title)
      expect(response).to have_http_status(:ok)
      expect(document.at_css("html")["lang"]).to eq("zh-CN")
      expect(document.css("h1").map(&:text)).to include(title)
    end

    { desktop: "developer-docs-q", mobile: "developer-docs-q-mobile" }.each do |region, field_id|
      it "keeps Chinese through generated navigation, #{region} search, clear, and missing-page recovery" do
        get admin_help_doc_path(customer.id, "getting-started", locale: :"zh-CN")
        expect_chinese_guide("开始使用工作区")

        related_link = document.css(".customer-doc a[href]").find { |link| link.text == "用户管理" }
        get related_link["href"]
        expect_chinese_guide("添加和管理用户")

        contents_link = document.css("nav[aria-label='目录'] a[href]").find { |link| link.text.strip == "快速入门" }
        get contents_link["href"]
        expect_chinese_guide("开始使用工作区")

        next_link = document.at_css("[data-docs-footer-sequence] a:last-child")
        get next_link["href"]
        expect_chinese_guide("将助手请求落实为已审核成果")

        previous_link = document.at_css("[data-docs-footer-sequence] a:first-child")
        get previous_link["href"]
        expect_chinese_guide("开始使用工作区")

        if region == :desktop
          breadcrumb = document.css("[data-docs-reader-center] > header a[href]").find { |link| link.text.strip == "全部指南" }
          get breadcrumb["href"]
          expect_chinese_guide("选择下一项工作区任务")
        end

        form = document.at_css("input##{field_id}").ancestors("form").first
        fields = form.css("input[name]").to_h { |input| [input["name"], input["value"]] }
        fields["q"] = "经批准的发送方"
        # GET form submission replaces the action's query string with form fields.
        search_url = URI.parse(form["action"]).path
        get search_url, params: fields

        expect_chinese_guide(region == :desktop ? "选择下一项工作区任务" : "开始使用工作区")
        expect(contents_links(:"zh-CN")).to eq([admin_help_doc_path(customer.id, "sms", locale: :"zh-CN")])
        expect(document.css("input[name='q']").map { |input| input["value"] }).to eq([fields["q"], fields["q"]])

        clear_link = document.css("[data-docs-nav-header] a").find { |link| link.text.strip == "清除搜索" }
        expect(Rack::Utils.parse_query(URI.parse(clear_link["href"]).query)).to eq("locale" => "zh-CN")
        get clear_link["href"]
        expect_chinese_guide(region == :desktop ? "选择下一项工作区任务" : "开始使用工作区")
        expect(contents_links(:"zh-CN").size).to eq(CustomerDocs::Catalog.slugs.size)
        expect(document.css("input[name='q']").map { |input| input["value"] }).to eq(["", ""])

        get admin_help_doc_path(customer.id, "not-a-customer-guide", locale: :"zh-CN")
        expect(response).to have_http_status(:not_found)
        expect(document.at_css("html")["lang"]).to eq("zh-CN")
        recovery_link = document.css("a[href]").find { |link| link.text.strip == "客户指南" }
        get recovery_link["href"]
        expect_chinese_guide("选择下一项工作区任务")

        help_link = document.at_css("a[role='menuitem'][href*='/admin/help/docs']")
        get help_link["href"]
        expect_chinese_guide("选择下一项工作区任务")
        expect(admin.reload.locale).to eq("en")
      end
    end
  end

  describe "missing or developer-only articles" do
    before { sign_in admin }

    %w[en zh-CN].each do |locale|
      %w[not-a-customer-guide entity-builder].each do |slug|
        it "returns a localized private 404 for #{slug} in #{locale}" do
          get admin_help_doc_path(customer.id, slug), params: { locale: locale }

          expect(response).to have_http_status(:not_found)
          expect_private_response
          expect(document.css("h1").map(&:text)).to include(I18n.t("customer_docs.missing_title", locale: locale))
          expect(response.body).to include(I18n.t("customer_docs.missing_body", locale: locale))
          expect(document.at_css(".customer-doc")).to be_nil
          expect(home_cards).to be_empty
          expect(document.at_css("a[href='#{admin_help_docs_path(customer.id, locale: locale)}']:not([role='menuitem'])")).not_to be_nil
        end
      end
    end
  end

  describe "tenant authorization before guide lookup" do
    it "denies a cross-tenant admin before looking up a nonexistent guide" do
      sign_in other_admin
      expect(CustomerDocs::Repository).not_to receive(:new)

      get admin_help_doc_path(customer.id, "not-a-customer-guide", locale: "zh-CN"), headers: json_headers

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to eq("error" => "access_denied")
      expect(home_cards).to be_empty
    end

    it "denies a member before looking up a nonexistent guide" do
      sign_in member
      expect(CustomerDocs::Repository).not_to receive(:new)

      get admin_help_doc_path(customer.id, "not-a-customer-guide", locale: "zh-CN"), headers: json_headers

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to eq("error" => "access_denied")
      expect(home_cards).to be_empty
    end
  end

  describe "separation from the platform developer reference" do
    let(:customer) { ensure_platform_customer }

    before { sign_in admin }

    {
      index: nil,
      article: "system-map"
    }.each do |endpoint, slug|
      it "redirects a non-owner platform admin away from the developer #{endpoint} for HTML" do
        path = slug ? admin_maintenance_platform_developer_doc_path(customer.id, slug) : admin_maintenance_platform_developer_docs_path(customer.id)
        get path

        expect(response).to have_http_status(:found)
        expect(URI.parse(response.location).path).to eq(URI.parse(admin_assistant_path(customer.id)).path)
      end

      it "forbids a non-owner platform admin requesting the developer #{endpoint} as JSON" do
        path = slug ? admin_maintenance_platform_developer_doc_path(customer.id, slug) : admin_maintenance_platform_developer_docs_path(customer.id)
        get path, headers: json_headers

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body).to eq("error" => "access_denied")
      end
    end
  end
end
