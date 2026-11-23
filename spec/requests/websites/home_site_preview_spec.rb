# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HomeSite composer and draft preview integration", type: :request do
  let!(:customer) { create(:customer, id: Websites::HomeSite::CUSTOMER_ID) }
  let!(:website_module) { enable_module!("website", customer, name: "Website") }
  let!(:site) { Websites::HomeSite.apply! }
  let(:admin) { create(:user, :admin, customer: customer) }
  let(:home) { site.home_page }
  let(:index_path) { "/#{customer.id}/admin/modules/website" }
  let(:preview_path) { "#{index_path}/pages/#{home.id}/preview" }

  before do
    Current.customer = customer
    sign_in admin
  end

  after { Current.reset }

  def snapshot
    [site.reload.attributes.deep_dup, site.pages.order(:id).map(&:attributes).deep_dup]
  end

  describe "preview authorization" do
    let(:guard_path) { preview_path }

    it_behaves_like "an admin-guarded GET"
    it_behaves_like "an admin-guarded request", :post

    it "rejects another tenant's admin on GET, POST and composer save without changing content" do
      before_content = snapshot
      other = create(:customer)
      foreign_admin = create(:user, :admin, customer: other)
      sign_in foreign_admin
      get preview_path
      expect(response).to redirect_to(Authentication::LandingPath.for(foreign_admin))
      post preview_path, params: { website_page: { title: "Intruder", sections_json: "[]" } }
      expect(response).to redirect_to(Authentication::LandingPath.for(foreign_admin))
      patch "#{index_path}/pages/#{home.id}", params: { website_page: { title: "Intruder", sections_json: "[]" } },
            headers: { "X-Website-Composer" => "1", "Accept" => "application/json" }
      expect(response).to have_http_status(:forbidden)
      expect(snapshot).to eq(before_content)
    end

    it "404s GET, POST and save for foreign record IDs on an authorized tenant URL" do
      other = create(:customer)
      foreign_site = create(:website, customer: other)
      foreign_page = create(:website_page, :home, website: foreign_site, title: "Foreign secret")
      before_foreign = foreign_page.attributes.deep_dup
      foreign_path = "#{index_path}/pages/#{foreign_page.id}"
      get "#{foreign_path}/preview"
      expect(response).to have_http_status(:not_found)
      post "#{foreign_path}/preview", params: { website_page: { title: "Intruder" } }
      expect(response).to have_http_status(:not_found)
      patch foreign_path, params: { website_page: { title: "Intruder" } },
            headers: { "X-Website-Composer" => "1", "Accept" => "application/json" }
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include("Foreign secret")
      expect(foreign_page.reload.attributes).to eq(before_foreign)
    end
  end

  it "uses the same scoped localized sections/artwork/footer in saved GET previews for every page without writes" do
    before_content = snapshot
    expect(Websites::HomeSite).not_to receive(:apply!)
    %w[en zh-CN en].each do |locale|
      source = Websites::HomeSite.definition(locale: locale)
      source.fetch("pages").each_with_index do |definition, index|
        page = site.pages.find_by!(slug: definition.fetch("slug"))
        get "#{index_path}/pages/#{page.id}/preview", params: { locale: locale, embed: 1 }
        expect(response).to have_http_status(:ok)
        html = Nokogiri::HTML(response.body)
        expect(html.at("title").text).to eq("#{definition.fetch('title')} · #{source.dig('seo', 'title')}")
        expect(html.at("meta[name='description']")["content"]).to eq(source.dig("seo", "description"))
        expect(html.css("main#site-main").size).to eq(1)
        expect(html.css("main h1").size).to eq(1)
        expect(html.css("main h1 > span").map(&:text)).to eq(definition.dig("sections", 0, "props", "headline").split("\n"))
        expect(html.css("main [data-site-section]").size).to eq([11, 9, 5, 6, 3].fetch(index))
        expect(html.css("main [data-site-section]").map { |node| node["data-site-section"] }).to eq(page.sections.pluck("id"))
        expect(html.css("main img").size).to eq([2, 2, 0, 2, 1].fetch(index))
        if page.slug == "about"
          expect(html.at("[data-site-section='home_site_about_hero'] img")["loading"]).to eq("eager")
          expect(html.css("[data-site-section='home_site_about_craft'] img").size).to eq(1)
        end
        expect(html.at("footer").text).to include(source.dig("footer", "blurb"))
      end
      expect(snapshot).to eq(before_content)
    end
  end

  it "localizes source-identical POST draft leaves while preserving unsaved literals, reordered lists and page identity" do
    draft = home.sections.deep_dup.reverse
    hero = draft.find { |section| section["type"] == "hero_centered" }
    hero["props"]["headline"] = "Unsaved owner headline\nStill a draft"
    preview = draft.find { |section| section["type"] == "ai_preview" }
    preview["props"]["items"].reverse!
    preview["props"]["items"].first["body"] = "Unsaved field outline\nOwner second line"
    before_content = snapshot

    %w[en zh-CN en].each do |locale|
      post preview_path, params: { locale: locale, embed: 1, website_page: { title: "Unsaved title", sections_json: draft.to_json } }
      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      expect(html.css("main#site-main").size).to eq(1)
      expect(html.css("main [data-site-section]").map { |node| node["data-site-section"] }).to eq(draft.pluck("id"))
      expect(html.css("main h1 > span").map(&:text)).to eq(["Unsaved owner headline", "Still a draft"])
      rendered_draft = html.at("[data-site-section='#{preview['id']}']")
      source_draft = Websites::HomeSite.definition(locale: locale).fetch("pages").first.fetch("sections").find { |section| section["type"] == "ai_preview" }
      expect(rendered_draft.css("h3").map(&:text)).to eq(source_draft.dig("props", "items").reverse.pluck("title"))
      expect(rendered_draft.at_css("article").css("li").map { |node| node.text.strip }).to eq(["Unsaved field outline", "Owner second line"])
      expect(rendered_draft.text).to include(source_draft.dig("props", "review_note"))
      source = Websites::HomeSite.definition(locale: locale)
      expect(html.at("title").text).to eq("Unsaved title · #{source.dig('seo', 'title')}")
      expect(html.at("meta[name='description']")["content"]).to eq(source.dig("seo", "description"))
      expect(snapshot).to eq(before_content)
    end
  end

  it "localizes source-identical draft titles after overlay rather than using the saved owner title" do
    home.update!(title: "Saved owner title")
    before_content = snapshot
    english_title = Websites::HomeSite.definition(locale: :en).fetch("pages").first.fetch("title")

    %w[en zh-CN].each do |locale|
      post preview_path, params: { locale: locale, website_page: { title: english_title } }
      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      source = Websites::HomeSite.definition(locale: locale)
      expect(html.at("title").text).to eq("#{source.fetch('pages').first.fetch('title')} · #{source.dig('seo', 'title')}")
      expect(html.at("meta[name='description']")["content"]).to eq(source.dig("seo", "description"))
      expect(html.css("main#site-main").size).to eq(1)
      expect(snapshot).to eq(before_content)
    end
  end

  it "preserves literal owner titles and SEO in both saved and embedded draft metadata without writes" do
    saved_title = "Owner <em>page</em>"
    draft_title = "Unsaved <em>page</em>"
    seo_title = "Owner <em>SEO</em>"
    description = 'Owner description with "quotes" and <em>literal markup</em>'
    home.update!(title: saved_title)
    site.update!(seo: { "title" => seo_title, "description" => description })
    before_content = snapshot

    %w[en zh-CN].each do |locale|
      get preview_path, params: { locale: locale }
      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      expect(html.at("title").text).to eq("#{saved_title} · #{seo_title}")
      expect(html.at("meta[name='description']")["content"]).to eq(description)

      post preview_path, params: { locale: locale, embed: 1, website_page: { title: draft_title } }
      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      expect(html.at("title").text).to eq("#{draft_title} · #{seo_title}")
      expect(html.at("meta[name='description']")["content"]).to eq(description)
      expect(html.css("head em")).to be_empty
      expect(html.css("main#site-main").size).to eq(1)
      expect(snapshot).to eq(before_content)
    end
  end

  it "retains another tenant's source-identical English preview metadata when Chinese is selected" do
    other = create(:customer)
    enable_module!("website", other, name: "Website")
    source = Websites::HomeSite.definition(locale: :en)
    other_site = create(:website, customer: other, **source.except("pages").symbolize_keys)
    other_page = create(:website_page, website: other_site, **source.fetch("pages").first.symbolize_keys)
    before_content = [other_site.attributes.deep_dup, other_page.attributes.deep_dup]
    sign_in create(:user, :admin, customer: other)

    get "/#{other.id}/admin/modules/website/pages/#{other_page.id}/preview", params: { locale: "zh-CN", embed: 1 }
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at("title").text).to eq("#{other_page.title} · #{source.dig('seo', 'title')}")
    expect(html.at("meta[name='description']")["content"]).to eq(source.dig("seo", "description"))
    expect(html.css("main#site-main")).to be_empty
    expect([other_site.reload.attributes, other_page.reload.attributes]).to eq(before_content)
  end

  it "filters unpublished/hidden destinations from Contact POST preview using localized saved nav records" do
    contact = site.pages.find_by!(slug: "contact")
    site.pages.find_by!(slug: "platform").update!(published: false)
    pricing = site.pages.find_by!(slug: "pricing")
    pricing.update!(title: "Owner pricing")
    before_content = snapshot
    post "#{index_path}/pages/#{contact.id}/preview", params: { locale: "zh-CN", website_page: { sections_json: contact.sections.to_json } }
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.css("main a").map { |node| [node.at("h3").text, node.at("p").text, node["href"]] }).to eq([
      ["Owner pricing", I18n.t("website.home_site.contact.routes.pricing", locale: "zh-CN"), "/pricing?locale=zh-CN"],
      [I18n.t("website.home_site.actions.create", locale: "zh-CN"), I18n.t("website.home_site.contact.routes.workspace", locale: "zh-CN"), "/auth/sign_up?locale=zh-CN"]
    ])
    expect(html.css("main a a, main a button")).to be_empty
    expect(snapshot).to eq(before_content)
    pricing.update!(nav_visible: false)
    post "#{index_path}/pages/#{contact.id}/preview", params: { locale: "zh-CN" }
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).css("main a").map { |node| node["href"] }).to eq(["/auth/sign_up?locale=zh-CN"])
    before_content = snapshot
    draft = contact.sections.deep_dup
    draft.find { |section| section["type"] == "cta_band" }["props"]["button_href"] = "javascript:alert(1)"
    post "#{index_path}/pages/#{contact.id}/preview", params: { locale: "zh-CN", website_page: { sections_json: draft.to_json } }
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.css("main a, main [role='button']")).to be_empty
    expect(html.at("main").text).not_to include(I18n.t("website.home_site.contact.routes.workspace", locale: "zh-CN"))
    expect(snapshot).to eq(before_content)
  end

  it "escapes unvalidated draft strings and rejects unsafe CTA/supplementary media without phantom buttons or placeholders" do
    hostile = '<img src=x onerror="alert(1)"><script>alert(1)</script>'
    draft = home.sections.deep_dup
    draft.first["props"].merge!("headline" => "#{hostile}\nLiteral second line", "primary_label" => hostile, "primary_href" => "javascript:alert(1)", "secondary_label" => "", "secondary_href" => "")
    desktop = draft.find { |section| section["type"] == "card_grid" }
    desktop.dig("props", "cards", 1).merge!("title" => hostile, "image_url" => "javascript:alert(1)", "href" => "javascript:alert(1)")
    desktop.dig("props", "cards", 2)["image_url"] = "/site-images/anysys/anysys-unknown.svg"
    desktop["props"]["cards"] << { "title" => hostile, "body" => hostile, "image_url" => "https://cdn.example.com/owner.webp" }
    closing = draft.find { |section| section["type"] == "cta_band" }
    closing["props"].merge!("headline" => hostile, "button_label" => "Invalid action", "button_href" => "data:text/html,bad")
    before_content = snapshot

    post preview_path, params: { locale: "zh-CN", website_page: { title: hostile, sections_json: draft.to_json } }
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    main = html.at("main")
    expect(main.css("script, [onerror], form, input, button, [role='button']")).to be_empty
    expect(main.css("h1 > span").map(&:text)).to eq([hostile, "Literal second line"])
    expect(main.css("a[href^='javascript:'], a[href^='data:']")).to be_empty
    expect(html.at("[data-site-section='#{draft.first['id']}']").css("a")).to be_empty
    rendered_closing = html.at("[data-site-section='#{closing['id']}']")
    actions = rendered_closing.css("span").select { |node| node.text == "Invalid action" }
    expect(actions.size).to eq(1)
    expect(rendered_closing.css("a, button, [role='button']")).to be_empty
    action = actions.first
    expect(action["class"]).not_to include("rounded", "bg-", "ring-")
    panel = html.at("[data-site-section='#{desktop['id']}']")
    expect(panel.css("img").map { |node| node["src"] }).to eq(["/site-images/anysys/anysys-photo-desktop-night.webp", "https://cdn.example.com/owner.webp"])
    expect(panel.at("figure img")["alt"]).to eq(hostile)
    expect(panel.css("figure svg")).to be_empty
    expect(snapshot).to eq(before_content)
  end

  it "round-trips actual headline newlines through the target textarea, locked composer save, reload and localized public render" do
    original = home.sections.deep_dup
    draft = original.deep_dup
    draft.first["props"]["headline"] = "Owner's saved first line\nOwner's saved second line"
    get "#{index_path}/pages/#{home.id}/edit"
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    hero = html.at("article[data-section-id='#{original.first['id']}']")
    expect(hero.at("textarea[data-prop='headline']").text).to eq(original.first.dig("props", "headline"))
    expect(hero.css("input[data-prop='headline']")).to be_empty
    expect(hero.at("[data-prop='media_mode']")).to be_present
    expect(hero.at("[data-prop='primary_href']")["value"]).to eq("/auth/sign_up")

    patch "#{index_path}/pages/#{home.id}", params: { website_page: { title: home.title, sections_json: draft.reverse.to_json } },
          headers: { "X-Website-Composer" => "1", "Accept" => "application/json" }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("ok" => true)
    expect(home.reload.sections).to eq(draft)
    expect(home.sections.drop(1)).to eq(original.drop(1))
    get "#{index_path}/pages/#{home.id}/edit"
    expect(Nokogiri::HTML(response.body).at("article[data-section-id='#{original.first['id']}'] textarea[data-prop='headline']").text).to eq(draft.first.dig("props", "headline"))
    get "/#{customer.id}/site", params: { locale: "zh-CN" }
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.css("main h1 > span").map(&:text)).to eq(["Owner's saved first line", "Owner's saved second line"])
    expect(html.css("main img").map { |node| node["src"] }).to eq(["/site-images/anysys/anysys-photo-desktop-night.webp", "/site-images/anysys/anysys-photo-studio-owner.webp"])
    expect(html.css("main [data-site-section]").map { |node| node["data-site-section"] }).to eq(original.pluck("id"))
  end
end
