# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HomeSite public language switching", type: :request do
  let!(:customer) { create(:customer, id: Websites::HomeSite::CUSTOMER_ID) }
  let!(:website_module) { enable_module!("website", customer, name: "Website") }
  let!(:site) { Websites::HomeSite.apply! }
  let(:home_path) { "/#{customer.id}/site" }

  after { Current.reset }

  def rendered_section(html, section)
    html.at_css("[data-site-section='#{section.fetch('id')}']")
  end

  def content_snapshot
    [site.reload.attributes.deep_dup, site.pages.order(:id).map(&:attributes).deep_dup]
  end

  def expect_read_only_content
    snapshot = content_snapshot
    writes = []
    subscriber = lambda do |event|
      sql = event.payload[:sql]
      writes << sql if sql.match?(/\A\s*(?:INSERT INTO|UPDATE|DELETE FROM)\s+"?(?:websites|website_pages)"?\s/i)
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
    expect(writes).to be_empty
    expect(content_snapshot).to eq(snapshot)
  end

  it "round-trips all five saved pages EN→ZH→EN with photo heroes, localized chrome/SEO and no writes" do
    artwork = [
      %w[desktop-night studio-owner], %w[desktop-night team-collab], [], %w[about-team craft], %w[contact]
    ].map { |names| names.map { |name| "anysys-photo-#{name}.webp" } }
    expect(Websites::HomeSite).not_to receive(:apply!)

    expect_read_only_content do
      %w[en zh-CN en].each do |locale|
        patch "/locale", params: { locale: locale }, headers: { "HTTP_REFERER" => home_path }
        expect(response).to have_http_status(:redirect)
        source = Websites::HomeSite.definition(locale: locale)
        source.fetch("pages").each_with_index do |page, index|
          get [home_path, page["slug"].presence].compact.join("/")
          expect(response).to have_http_status(:ok)
          html = Nokogiri::HTML(response.body)
          expect(html.at("html")["lang"]).to eq(locale)
          expect(html.at("title").text).to eq("#{page['title']} · #{source.dig('seo', 'title')}")
          expect(html.at("meta[name='description']")["content"]).to eq(source.dig("seo", "description"))
          expect(html.css("main#site-main[tabindex='-1']").size).to eq(1)
          expect(html.css("main h1").size).to eq(1)
          expect(html.css("main h1 > span").map(&:text)).to eq(page.dig("sections", 0, "props", "headline").split("\n"))
          expect(rendered_section(html, page.fetch("sections").first).css("p").map(&:text)).to include(page.dig("sections", 0, "props", "subhead"))
          expect(html.css("main [data-site-section]").size).to eq([11, 9, 5, 6, 3].fetch(index))
          expect(html.css("main [data-site-section]").map { |node| node["data-site-section"] }).to eq(page.fetch("sections").pluck("id"))
          hero = rendered_section(html, page.fetch("sections").first)
          if %w[about contact].include?(page["slug"])
            expect(hero.css("img").map { |image| image["src"] }).to eq([page.dig("sections", 0, "props", "image_url")])
            expect(hero.at("img")["loading"]).to eq("eager")
          end
          if page["slug"] == "about"
            craft = page.fetch("sections").find { |section| section["id"] == "home_site_about_craft" }
            expect(craft.fetch("type")).to eq("split_image_text")
            expect(rendered_section(html, craft).css("img").map { |image| image["src"] }).to eq([craft.dig("props", "image_url")])
            expect(rendered_section(html, craft).at("h2").text).to eq(craft.dig("props", "heading"))
          end
          unless %w[about contact].include?(page["slug"])
            expect(hero.css("img")).to be_empty
            hero.css("svg").each do |svg|
              expect(svg["focusable"]).to eq("false")
              expect([svg, *svg.ancestors].any? { |node| node["aria-hidden"] == "true" }).to be(true)
            end
          end
          if page["slug"] == "pricing"
            foundation = page.fetch("sections").find { |section| section["id"] == "home_site_pricing_foundation" }
            rendered_foundation = rendered_section(html, foundation)
            expect(rendered_foundation.at("h2").text).to eq(foundation.dig("props", "heading"))
            expect(rendered_foundation.css("h3").map(&:text)).to eq(foundation.dig("props", "items").pluck("title"))
            expect(rendered_foundation.css("article p").map(&:text)).to eq(foundation.dig("props", "items").pluck("body"))
          end
          images = html.css("main img")
          expect(images.map { |image| File.basename(image["src"]) }).to eq(artwork.fetch(index))
          expect(images.map { |image| image["alt"] }).to all(be_present)
          expect(html.css("main svg").count { |svg| svg.at_css("text") }).to eq(0)
          expect(html.at("footer").text).to include(source.dig("footer", "blurb"), source.fetch("tagline"))
          expect(html.css("header nav a").map { |link| link.text.strip }).to eq(source.fetch("pages").pluck("title"))
          expect(html.css("header nav a[aria-current='page']").map { |link| link.text.strip }).to eq([page.fetch("title")])
          signup_href = locale == "en" ? "/auth/sign_up" : "/auth/sign_up?locale=#{locale}"
          expect(html.at("header a[href='#{signup_href}']").text).to eq(I18n.t("website.home_site.actions.start", locale: locale))
          expect(html.css("#website-nav-panel a[href='#{signup_href}']").size).to eq(1)
          expect(html.css("main form, main input, main textarea, main select, main button, main [role='button'], main a[download]")).to be_empty
          destinations = html.css("main a").map { |link| Addressable::URI.parse(link["href"]).path }.uniq
          expect(destinations - ["/auth/sign_up", "/platform", "/pricing"]).to be_empty
        end
      end
    end
  end

  it "follows locale links while preserving literal edits, saved order, reordered feature/draft lists and inserted known sections" do
    home = site.home_page
    sections = home.sections.deep_dup.reverse
    hero = sections.find { |section| section["type"] == "hero_centered" }
    hero["props"].merge!("headline" => "Owner's headline\nSecond line", "primary_href" => "/owner/start?campaign=illustration")
    grid = sections.find { |section| section["type"] == "feature_grid" }
    grid["props"]["items"].reverse!
    grid["props"]["items"].first.merge!("title" => "Owner's capability", "body" => "Owner's explanation\nSecond line")
    draft = sections.find { |section| section["type"] == "ai_preview" }
    draft["props"]["items"].reverse!
    sections.insert(1, { "id" => "owner_quote", "type" => "quote", "props" => { "quote" => "Owner's inserted quotation", "attribution" => "Owner" } })
    home.update!(title: "Owner home", sections: sections)
    site.update!(footer: site.footer.merge("blurb" => "Owner's footer"))
    expect(Websites::HomeSite).not_to receive(:apply!)

    selected_path = "#{home_path}?locale=en"
    locales = %w[en zh-CN en]
    expect_read_only_content do
      locales.each_with_index do |locale, index|
        get selected_path
        expect(response).to have_http_status(:ok)
        html = Nokogiri::HTML(response.body)
        expect(html.at("html")["lang"]).to eq(locale)
        expect(html.at("title").text).to start_with("Owner home · ")
        expect(html.css("main [data-site-section]").map { |section| section["data-site-section"] }).to eq(sections.pluck("id"))
        expect(html.at("footer").text).to include("Owner's footer")
        rendered_hero = rendered_section(html, hero)
        expect(rendered_hero.css("h1 > span").map(&:text)).to eq(["Owner's headline", "Second line"])
        expect(rendered_hero.css("img")).to be_empty
        expect(rendered_hero.css("svg").map { |svg| svg["aria-hidden"] || svg.ancestors.any? { |node| node["aria-hidden"] == "true" } }).to all(be_truthy)
        expect(rendered_hero.css("a").map { |link| link["href"] }).to include("/owner/start?campaign=illustration&locale=#{locale}")
        source = Websites::HomeSite.definition(locale: locale).fetch("pages").first.fetch("sections")
        source_grid = source.find { |section| section["id"] == grid["id"] }
        rendered_grid = rendered_section(html, grid)
        expect(rendered_grid.css("h3").map(&:text)).to eq(["Owner's capability", *source_grid.dig("props", "items").reverse.drop(1).pluck("title")])
        expect(rendered_grid.text).to include("Owner's explanation\nSecond line")
        expect(rendered_grid.css("img")).to be_empty
        rendered_draft = rendered_section(html, draft)
        source_draft = source.find { |section| section["type"] == "ai_preview" }
        expect(rendered_draft.css("h3").map(&:text)).to eq(source_draft.dig("props", "items").reverse.pluck("title"))
        expect(rendered_draft.css("article li").map { |node| node.text.strip }).to eq(source_draft.dig("props", "items").reverse.flat_map { |item| item.fetch("body").lines.map(&:strip) })
        expect(html.at("[data-site-section='owner_quote']").text).to include("Owner's inserted quotation")
        next_locale = locales[index + 1]
        next unless next_locale

        switch_link = html.css("a").find { |link| link["href"] == "#{home_path}?locale=#{next_locale}" }
        expect(switch_link).to be_present
        selected_path = switch_link["href"]
      end
    end
  end

  it "keeps owner metadata and publication/nav visibility authoritative" do
    home = site.home_page
    sections = home.sections.deep_dup
    sections.first["props"]["headline"] = "Owner's public headline"
    home.update!(title: "Owner home", sections: sections)
    site.update!(seo: { "title" => "Owner SEO", "description" => "Owner description" })
    site.pages.find_by!(slug: "contact").update!(published: false)
    site.pages.find_by!(slug: "about").update!(nav_visible: false)
    get home_path, params: { locale: "zh-CN" }
    html = Nokogiri::HTML(response.body)
    expect(html.at("title").text).to eq("Owner home · Owner SEO")
    expect(html.at("meta[name='description']")["content"]).to eq("Owner description")
    expect(html.at("main h1").text.strip).to eq("Owner's public headline")
    nav_hrefs = html.css("header nav a, #website-nav-panel nav a").map { |link| URI.parse(link["href"]).path }
    expect(nav_hrefs).not_to include("/contact", "/about")
    get "#{home_path}/contact"
    expect(response).to have_http_status(:not_found)
    expect(response.body).to be_empty
    site.update!(published: false)
    get home_path
    expect(response).to have_http_status(:not_found)
    expect(response.body).to be_empty
  end

  it "preserves custom story and supplementary card media with localized alt/link context and no custom overlays" do
    home = site.home_page
    sections = home.sections.deep_dup
    custom_image = "https://cdn.example.com/owner-story.webp?signature=abc&expires=123"
    story = sections.find { |section| section["type"] == "split_image_text" }
    story["props"]["image_url"] = custom_image
    desktop = sections.find { |section| section["type"] == "card_grid" }
    desktop.dig("props", "cards", 1).merge!("image_url" => "https://cdn.example.com/owner-card.webp", "href" => "about")
    desktop.dig("props", "cards", 2).merge!("image_url" => "/81721200/site/media/owner--signed", "title" => "Owner's private image")
    home.update!(sections: sections)

    expect_read_only_content do
      %w[en zh-CN en].each do |locale|
        get home_path, params: { locale: locale }
        expect(response).to have_http_status(:ok)
        html = Nokogiri::HTML(response.body)
        image = rendered_section(html, story).at_css("img")
        source = Websites::HomeSite.definition(locale: locale).fetch("pages").first.fetch("sections")
        expect(image["src"]).to eq(custom_image)
        expect(image["alt"]).to eq(source.find { |section| section["type"] == "split_image_text" }.dig("props", "heading"))
        expect(image["loading"]).to eq("lazy")
        expect(image.parent.css("svg")).to be_empty
        panel = rendered_section(html, desktop)
        expect(panel.css("img").map { |node| node["src"] }).to eq(["/site-images/anysys/anysys-photo-desktop-night.webp", "https://cdn.example.com/owner-card.webp", "/81721200/site/media/owner--signed"])
        expect(panel.css("figure img").map { |node| node["alt"] }).to eq([source.find { |section| section["type"] == "card_grid" }.dig("props", "cards", 1, "title"), "Owner's private image"])
        expect(panel.css("figure svg")).to be_empty
        expect(panel.css("a").map { |node| node["href"] }).to include("/about?locale=#{locale}")
        expect(html.css("main svg").count { |svg| svg.at_css("text") }).to eq(0)
      end
    end
  end

  it "takes Contact next steps from published nav-visible pages in saved order and preserves custom labels" do
    platform = site.pages.find_by!(slug: "platform")
    pricing = site.pages.find_by!(slug: "pricing")
    platform.update!(title: "Owner platform", position: 9)
    pricing.update!(position: 1)
    expect_read_only_content do
      get "#{home_path}/contact", params: { locale: "zh-CN" }
      html = Nokogiri::HTML(response.body)
      closing = html.at("main [data-site-section='home_site_contact_cta']")
      expect(closing.css("a").map { |node| [node.at("h3").text, node.at("p").text, node["href"]] }).to eq([
        ["价格", I18n.t("website.home_site.contact.routes.pricing", locale: "zh-CN"), "/pricing?locale=zh-CN"],
        ["Owner platform", I18n.t("website.home_site.contact.routes.platform", locale: "zh-CN"), "/platform?locale=zh-CN"],
        [I18n.t("website.home_site.actions.create", locale: "zh-CN"), I18n.t("website.home_site.contact.routes.workspace", locale: "zh-CN"), "/auth/sign_up?locale=zh-CN"]
      ])
      expect(closing.css("a a, a button")).to be_empty
    end
    pricing.update!(published: false)
    platform.update!(nav_visible: false)
    expect_read_only_content do
      get "#{home_path}/contact", params: { locale: "zh-CN" }
      html = Nokogiri::HTML(response.body)
      expect(html.css("main a").map { |node| node["href"] }).to eq(["/auth/sign_up?locale=zh-CN"])
      expect(html.css("main a h3").map(&:text)).to eq([I18n.t("website.home_site.actions.create", locale: "zh-CN")])
      expect(html.at("main a p").text).to eq(I18n.t("website.home_site.contact.routes.workspace", locale: "zh-CN"))
      expect(html.css("header nav a").map { |node| node["href"] }).not_to include("/pricing?locale=zh-CN", "/platform?locale=zh-CN")
    end
  end

  it "preserves edited Pricing foundation and About craft copy/order without restoring removed hero media on language reads" do
    pricing = site.pages.find_by!(slug: "pricing")
    pricing_sections = pricing.sections.deep_dup.reverse
    foundation = pricing_sections.find { |section| section["id"] == "home_site_pricing_foundation" }
    foundation["props"]["heading"] = "Owner's connected workspace"
    foundation["props"]["items"].reverse!
    foundation["props"]["items"].first.merge!("title" => "Owner's service", "body" => "Owner's service description")
    pricing.update!(sections: pricing_sections)
    about = site.pages.find_by!(slug: "about")
    about_sections = about.sections.deep_dup.reverse
    hero = about_sections.find { |section| section["type"] == "hero_centered" }
    hero["props"].merge!("media_mode" => "none", "image_url" => "")
    craft = about_sections.find { |section| section["id"] == "home_site_about_craft" }
    craft["props"].merge!("heading" => "Owner's craft", "body" => "Owner's first paragraph\n\nOwner's second paragraph")
    about.update!(sections: about_sections)
    expect(Websites::HomeSite).not_to receive(:apply!)

    expect_read_only_content do
      %w[en zh-CN en].each do |locale|
        get "#{home_path}/pricing", params: { locale: locale }
        expect(response).to have_http_status(:ok)
        html = Nokogiri::HTML(response.body)
        expect(html.css("main [data-site-section]").map { |node| node["data-site-section"] }).to eq(pricing_sections.pluck("id"))
        rendered_foundation = rendered_section(html, foundation)
        expect(rendered_foundation.at("h2").text).to eq("Owner's connected workspace")
        source_items = Websites::HomeSite.definition(locale: locale).fetch("pages").find { |page| page["slug"] == "pricing" }.fetch("sections").find { |section| section["id"] == foundation["id"] }.dig("props", "items")
        expect(rendered_foundation.css("h3").map(&:text)).to eq(["Owner's service", *source_items.reverse.drop(1).pluck("title")])
        expect(rendered_foundation.css("p").map(&:text)).to include("Owner's service description")

        get "#{home_path}/about", params: { locale: locale }
        expect(response).to have_http_status(:ok)
        html = Nokogiri::HTML(response.body)
        expect(html.css("main [data-site-section]").map { |node| node["data-site-section"] }).to eq(about_sections.pluck("id"))
        expect(html.css("main img").map { |image| image["src"] }).to eq([craft.dig("props", "image_url")])
        rendered_craft = rendered_section(html, craft)
        expect(rendered_craft.at("h2").text).to eq("Owner's craft")
        expect(rendered_craft.css("p").map(&:text)).to include("Owner's first paragraph", "Owner's second paragraph")
      end
    end
  end

  it "omits blank or unsafe saved workspace routes while retaining the published Contact page cards" do
    contact = site.pages.find_by!(slug: "contact")
    ["", "javascript:alert(1)"].each do |destination|
      sections = contact.sections.deep_dup
      sections.find { |section| section["type"] == "cta_band" }["props"]["button_href"] = destination
      contact.update!(sections: sections)
      expect_read_only_content do
        get "#{home_path}/contact", params: { locale: "zh-CN" }
        expect(response).to have_http_status(:ok)
        html = Nokogiri::HTML(response.body)
        closing = html.at("main [data-site-section='home_site_contact_cta']")
        expect(closing.css("a").map { |node| node["href"] }).to eq(["/platform?locale=zh-CN", "/pricing?locale=zh-CN"])
        expect(closing.css("h3").map(&:text)).to eq(["平台", "价格"])
        expect(closing.text).not_to include(I18n.t("website.home_site.contact.routes.workspace", locale: "zh-CN"))
        expect(closing.css("a a, a button, [role='button']")).to be_empty
      end
    end
  end

  it "keeps extra owner pages on generic sections and chrome even with identical source IDs and wording" do
    source = Websites::HomeSite.definition.fetch("pages").first
    extra = create(:website_page, website: site, customer: customer, slug: "campaign", title: "Owner campaign", published: true, sections: source.fetch("sections"))
    expect_read_only_content do
      get "#{home_path}/campaign", params: { locale: "zh-CN" }
      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      expect(html.at("main h1").text).to eq(source.dig("sections", 0, "props", "headline"))
      expect(html.css("#site-main, header a[href^='/auth/sign_up']")).to be_empty
      expect(extra.reload.sections).to eq(source.fetch("sections"))
    end
  end

  it "excludes a foreign-customer page attached to this site from public lookup, scoped nav and Contact next steps" do
    site.pages.find_by!(slug: "pricing").update!(slug: "original-pricing")
    foreign = create(:customer)
    page = create(:website_page, :published, website: site, customer: foreign, slug: "pricing", title: "Foreign pricing", sections: [
      { "id" => "foreign", "type" => "rich_text", "props" => { "body" => "Foreign price details" } }
    ])
    before_foreign = page.attributes.deep_dup
    expect_read_only_content do
      get "#{home_path}/pricing", params: { locale: "zh-CN" }
      expect(response).to have_http_status(:not_found)
      expect(response.body).to be_empty
      get "#{home_path}/contact", params: { locale: "zh-CN" }
      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      expect(html.css("header nav a, #website-nav-panel nav a").map(&:text)).not_to include("Foreign pricing")
      expect(html.css("main a").map { |node| node["href"] }).to eq(["/platform?locale=zh-CN", "/auth/sign_up?locale=zh-CN"])
      expect(response.body).not_to include("Foreign price details")
      expect(page.reload.attributes).to eq(before_foreign)
    end
  end

  it "does not localize or scope the redesign to another tenant even with identical source text" do
    other = create(:customer)
    enable_module!("website", other, name: "Website")
    source = Websites::HomeSite.definition
    other_site = create(:website, customer: other, **source.except("pages").symbolize_keys)
    other_page = create(:website_page, website: other_site, published: true, **source["pages"].first.symbolize_keys)
    before_other = [other_site.attributes.deep_dup, other_page.attributes.deep_dup]
    get "/#{other.id}/site", params: { locale: "zh-CN" }
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at("main h1").text).to eq(source.dig("pages", 0, "sections", 0, "props", "headline"))
    expect(html.css("#site-main, header a[href^='/auth/sign_up']")).to be_empty
    expect([other_site.reload.attributes, other_page.reload.attributes]).to eq(before_other)
  end

  it "retains either explicit language through header, mobile, section, footer and signup links despite an opposing cookie" do
    [["en", "zh-CN"], ["zh-CN", "en"]].each do |saved, selected|
      patch "/locale", params: { locale: saved }
      get home_path, params: { locale: selected }
      html = Nokogiri::HTML(response.body)
      expect(html.at("html")["lang"]).to eq(selected)
      expect(html.css("main h1 > span").map(&:text)).to eq(Websites::HomeSite.definition(locale: selected).dig("pages", 0, "sections", 0, "props", "headline").split("\n"))
      links = html.css("header a:not([role='menuitem']), #website-nav-panel a, main a, footer a").filter_map { |link| link["href"] if link["href"]&.start_with?("/") }
      expect(links).not_to be_empty
      links.each do |href|
        expect(Addressable::URI.parse(href).query_values(Array).select { |key, _| key == "locale" }).to eq([["locale", selected]])
      end
      expect(links).to include("/auth/sign_up?locale=#{selected}")
      section_link = html.css("main a").find { |link| Addressable::URI.parse(link["href"]).path == "/platform" }
      get section_link["href"]
      expect(Nokogiri::HTML(response.body).at("html")["lang"]).to eq(selected)
      footer_link = Nokogiri::HTML(response.body).css("footer a").find { |link| Addressable::URI.parse(link["href"]).path == "/pricing" }
      get footer_link["href"]
      expect(Nokogiri::HTML(response.body).at("html")["lang"]).to eq(selected)
      expect(Nokogiri::HTML(response.body).at("main h1").text.strip).to eq(Websites::HomeSite.definition(locale: selected).fetch("pages").find { |page| page["slug"] == "pricing" }.dig("sections", 0, "props", "headline"))
    end
  end

  it "keeps default-English signup URLs unchanged in the desktop header, mobile sheet and page" do
    get home_path
    html = Nokogiri::HTML(response.body)
    expect(html.css("header a[href='/auth/sign_up']").size).to eq(1)
    expect(html.css("#website-nav-panel a[href='/auth/sign_up']").size).to eq(1)
    expect(html.css("main a").map { |link| link["href"] }).to include("/auth/sign_up")
  end
end
