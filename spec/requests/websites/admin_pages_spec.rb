# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Websites::Admin::Pages", type: :request do
  let_it_be(:customer) { create(:customer) }
  let!(:website_module) { enable_module!("website", customer, name: "Website") }
  let(:admin) { create(:user, :admin, customer: customer, password: "password123") }
  let(:index_path) { "/#{customer.id}/admin/modules/website" }
  let(:guard_path) { index_path }

  before do
    Current.customer = customer
    sign_in admin
  end

  it_behaves_like "an admin-guarded GET"

  describe "GET new — auth guards" do
    let(:guard_path) { "#{index_path}/pages/new" }

    it_behaves_like "an admin-guarded GET"
  end

  describe "POST create — auth guards" do
    let(:guard_path) { "#{index_path}/pages" }

    it_behaves_like "an admin-guarded request", :post
  end

  describe "GET settings — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/settings/modules/website" }

    it_behaves_like "an admin-guarded GET"
  end


  def website_records_available?
    website = "Website".safe_constantize
    page = "WebsitePage".safe_constantize
    website&.table_exists? && page&.table_exists? &&
      FactoryBot.factories.registered?(:website) &&
      FactoryBot.factories.registered?(:website_page)
  end

  def disable_website_module!
    FeatureModules::CustomerAssignment.find_by!(
      customer: customer, feature_module: FeatureModules::Module.find_by!(key: "website")
    ).update!(status: :suspended)
  end

  it "GET /admin/modules/website lists site pages for an admin" do
    skip "Website factory not available" unless website_records_available?

    Current.customer = customer
    site = create(:website, customer: customer, published: false)
    create(:website_page, :home, website: site, customer: customer)

    get index_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("website.admin.pages.index.title"))
    document = Nokogiri::HTML(response.body)
    main = document.at_css("main")
    expect(document.css("aside a[href='#{index_path}'][aria-current='page']")).to be_present
    expect(document.css("aside a[href='/#{customer.id}/admin/pages/website']")).to be_empty
    expect(main.css("a[href='#{index_path}/pages/new']")).to be_present
    expect(main.css('a[href*="/admin/settings/modules/"], a[href*="/admin/modules/website/publication"]')).to be_empty
    expect(main.text).not_to include(I18n.t("website.admin.pages.index.publish_site"))
  end

  it "labels list rows with the same public address the editor shows" do
    site = create(:website, customer: customer)
    pages = [create(:website_page, :home, website: site, customer: customer), create(:website_page, website: site, customer: customer, title: "Pricing", slug: "pricing")]

    get index_path

    subtitles = Nokogiri::HTML(response.body).css("main p.truncate").map { |node| node.text.strip }
    pages.each do |page|
      expect(subtitles).to include(PageShortcuts::PublicPath.website_page(page: page, host: "www.example.com"))
    end
    expect(subtitles).not_to include("/#{customer.id}/site", "/#{customer.id}/site/pricing")
  end

  it "uses clean root paths for the platform marketing site list" do
    platform = Customer.find_by(id: Websites::HomeSite::CUSTOMER_ID) || create(:customer, id: Websites::HomeSite::CUSTOMER_ID)
    enable_module!("website", platform, name: "Website")
    site = create(:website, customer: platform)
    create(:website_page, :home, website: site, customer: platform)
    create(:website_page, website: site, customer: platform, title: "Pricing", slug: "pricing")
    sign_in create(:user, :admin, customer: platform)

    get "/#{platform.id}/admin/modules/website"

    subtitles = Nokogiri::HTML(response.body).css("main p.truncate").map { |node| node.text.strip }.uniq
    expect(subtitles).to include("/", "/pricing")
    expect(subtitles).not_to include("/#{platform.id}/site", "/#{platform.id}/site/pricing")
  end

  it "does not serve Website pages through the old Pages URL" do
    get "/#{customer.id}/admin/pages/website"
    expect(response).to have_http_status(:not_found)
  end

  it "uses the module list as the return destination after deleting a page" do
    site = create(:website, customer: customer)
    page = create(:website_page, website: site, customer: customer, title: "About", slug: "about")

    delete "#{index_path}/pages/#{page.id}"

    expect(response).to redirect_to(index_path)
    expect(WebsitePage.exists?(page.id)).to be(false)
  end

  it "keeps list pagination, search and edit links under the module" do
    site = create(:website, customer: customer)
    page = create(:website_page, website: site, customer: customer, title: "About", slug: "about")

    get index_path, params: { q: "About" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(page.title)
    expect(Nokogiri::HTML(response.body).at_css("main a[href='#{index_path}/pages/#{page.id}/edit']")).to be_present
    expect(response.body).not_to include("/admin/pages/website")
  end

  it "GET settings is allowed for an admin when the module is enabled" do
    get "/#{customer.id}/admin/settings/modules/website"
    expect(response).to have_http_status(:ok)
  end

  it "GET new is allowed for an admin when the module is enabled" do
    get "#{index_path}/pages/new"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("lg:w-72")
    document = Nokogiri::HTML(response.body)
    expect(document.css('[name="website_page[slug]"]')).to be_empty
    expect(document.at_css("form#website-page-form [data-new-page-shell]")).to be_present
    expect(document.at_css("#website-page-identity-heading").text).to eq(I18n.t("website.admin.pages.new.details_heading"))
  end

  it "forbids a member on the admin index" do
    sign_in create(:user, :member, customer: customer)
    get index_path
    expect(response).to have_http_status(:forbidden)
      .or have_http_status(:found)
      .or have_http_status(:not_found)
  end

  it "returns 404 when the Website module is disabled" do
    disable_website_module!
    get index_path
    expect(response).to have_http_status(:not_found)
  end

  it "returns 404 for settings when the Website module is disabled" do
    disable_website_module!
    get "/#{customer.id}/admin/settings/modules/website"
    expect(response).to have_http_status(:not_found)
  end

  it "does not admit an admin of another customer on this tenant's URL" do
    other = create(:customer)
    sign_in create(:user, :admin, customer: other)
    get index_path
    expect(response).to have_http_status(:not_found)
      .or have_http_status(:forbidden)
      .or have_http_status(:found)
  end

  it "returns 404 for another tenant's page id" do
    skip "Website factory not available" unless website_records_available?

    other = create(:customer)
    Current.customer = other
    other_site = create(:website, customer: other)
    leak = create(:website_page, website: other_site, customer: other, title: "Secret", slug: "secret")
    Current.customer = customer

    get "#{index_path}/pages/#{leak.id}/edit"
    expect(response).to have_http_status(:not_found)
  end

  it "GET preview is allowed for a tenant page and 404s across tenants" do
    skip "Website factory not available" unless website_records_available?

    Current.customer = customer
    site = create(:website, customer: customer)
    page = create(:website_page, :home, website: site, customer: customer)

    get "#{index_path}/pages/#{page.id}/preview"
    expect(response).to have_http_status(:ok)

    other = create(:customer)
    Current.customer = other
    other_site = create(:website, customer: other)
    leak = create(:website_page, :home, website: other_site, customer: other)
    Current.customer = customer

    get "#{index_path}/pages/#{leak.id}/preview"
    expect(response).to have_http_status(:not_found)
  end

  it "GET edit composes all four content tabs with direct actions and compact identifiable cards in both locales" do
    skip "Website factory not available" unless website_records_available?

    Current.customer = customer
    site = create(:website, customer: customer)
    create(:website_page, website: site, customer: customer, title: "Team", slug: "team")
    page_record = create(
      :website_page,
      website: site,
      customer: customer,
      title: "About",
      slug: "about",
      sections: [
        {
          "id" => "sec_hero",
          "type" => "hero_cinematic",
          "props" => {
            "headline" => "Hello",
            "primary_href" => "team",
            "image_url" => "https://cdn.example/hero.jpg"
          }
        },
        {
          "id" => "sec_cards",
          "type" => "card_grid",
          "props" => { "heading" => "Our team", "cards" => [{ "title" => "People", "href" => "team" }, { "title" => "Studio", "body" => "Our space" }] }
        },
        {
          "id" => "sec_quote", "type" => "quote",
          "props" => { "quote" => "Make it beautiful.", "attribution" => "Studio", "role" => "Designers" }
        },
        {
          "id" => "sec_cta", "type" => "cta_band",
          "props" => { "headline" => "Visit", "body" => "Meet us", "button_label" => "Our team", "button_href" => "team" }
        }
      ]
    )

    %w[en zh-CN].each do |locale|
      get "#{index_path}/pages/#{page_record.id}/edit", params: { locale: locale }
      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      editor = document.at_css('[data-website-builder-target="editorPane"]')
      expect(editor["class"]).to include("xl:w-[28rem]", "xl:max-w-[38%]")
      expect(editor.css('[data-workspace-section-nav][role="tablist"]').size).to eq(1)
      expect(editor.at_css("[data-workspace-outline]")).to be_present
      expect(editor.at_css("[data-workspace-detail]")["class"]).to include("hidden")
      expect(editor.at_css("[data-workspace-identity-nav]").text).to include(
        I18n.t("website.admin.pages.edit.page_settings", locale: locale)
      )
      expect(editor.at_css("[data-identity-panel]")["class"]).to include("hidden")
      expect(editor.at_css("[data-identity-panel] #website-page-identity-heading").text.strip).to eq(
        I18n.t("website.admin.pages.edit.page_settings", locale: locale)
      )
      expect(editor.css('[name="website_page[slug]"]')).to be_empty

      tabs = editor.css('[data-workspace-section-nav] [role="tab"]')
      expect(tabs.size).to eq(4)
      tabs.each_with_index do |tab, index|
        panel = editor.at_css("##{tab['aria-controls']}")
        expect(panel["role"]).to eq("tabpanel")
        expect(panel["aria-labelledby"]).to eq(tab["id"])
        expect(tab["aria-selected"]).to eq(index.zero?.to_s)
        expect(tab["tabindex"]).to eq(index.zero? ? "0" : "-1")
      end

      hero = editor.at_css('[data-section-type="hero_cinematic"]')
      expect(hero.at_css('input[data-prop="headline"]')["value"]).to eq("Hello")
      expect(editor.css('details[data-field-group]')).to be_empty
      expect(hero.at_css('details[data-button-pair="secondary"]')["open"]).to be_nil
      expect(hero.at_css('[data-button-pair="primary"] fieldset [data-prop="primary_href"]')).to be_present
      expect(hero.at_css('[data-href-toggle]')["aria-expanded"]).to eq("false")
      expect(hero.at_css('[data-href-picker]')["class"]).to include("hidden")
      expect(hero.css('select[data-prop]')).to be_empty
      expect(hero.css('[data-prop="tone"][type="radio"]').size).to eq(2)
      expect(hero.at_css('[data-prop="subhead"]')["rows"]).to eq("2")
      expect(hero.at_css('[data-prop="primary_href"]')["value"]).to eq("team")
      expect(hero.at_css('[data-prop="image_url"]')["value"]).to eq("https://cdn.example/hero.jpg")
      cards = editor.css('[data-array="cards"] > [data-array-list] > details[data-array-item]')
      expect(cards.size).to eq(2)
      expect(cards.first.key?("open")).to be(true)
      expect(cards.last.key?("open")).to be(false)
      expect(cards.first.at_css('summary [data-item-title]').text).to eq("People")
      expect(cards.last.at_css('summary [data-item-title]').text).to eq("Studio")
      expect(editor.at_css('[data-array-count]').text).to eq("2")
      expect(cards.first.at_css('[data-prop="body"]')["rows"]).to eq("2")
      quote = editor.at_css('[data-section-type="quote"]')
      expect(quote.at_css('[data-prop="quote"]')["rows"]).to eq("3")
      expect(quote.at_css('[data-prop="attribution"]').parent.parent.css('[data-prop="role"]').size).to eq(1)
      cta = editor.at_css('[data-section-type="cta_band"]')
      expect(cta.at_css('[data-button-pair="button"] fieldset [data-prop="button_href"]')["value"]).to eq("team")
      expect(cta.at_css('[data-prop="body"]')["rows"]).to eq("3")
      expect(editor.css('[data-action*="resetSection"]').size).to eq(4)
      expect(editor.css('[data-section-position]').size).to eq(4)
      expect(editor.css('[data-section-step="next"]').map { |step| step["data-section-id"] }).to eq(%w[sec_cards sec_quote sec_cta])
      address = document.at_css("[data-page-address]")
      expect(address.text).to include("/#{customer.id}/about", I18n.t("website.admin.pages.edit.address_hidden", locale: locale))
      expect(address.at_css("a")).to be_nil
      expect(document.at_css("[data-preview-address]").text).to include("/#{customer.id}/about")
    end

    site.update!(published: true)
    page_record.update!(published: true)
    get "#{index_path}/pages/#{page_record.id}/edit", params: { locale: "en" }
    expect(Nokogiri::HTML(response.body).at_css("[data-page-address] a[target='_blank']")["href"]).to eq("/#{customer.id}/about")

    get "#{index_path}/pages/#{page_record.id}/edit", params: { locale: "en" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("website.admin.pages.edit.page_settings"))
    expect(response.body).to include(I18n.t("website.admin.pages.edit.sections"))
    expect(response.body).to include(I18n.t("website.admin.pages.form.reset_content"))
    expect(response.body).to include(I18n.t("website.admin.pages.form.href_picker"))
    expect(Nokogiri::HTML(response.body).css('option[value="team"]').map(&:text).uniq).to eq(["Team"])
    expect(response.body).to include(%(data-website-builder-structure-locked-value="true"))
    expect(response.body).to include(%(data-workspace-rail))
    expect(response.body).not_to include("xl:w-52")
    expect(response.body).to include(I18n.t("website.admin.pages.edit.back_to_sections"))
    expect(Nokogiri::HTML(response.body).css("[data-field-section] > h3, [data-field-section] > h4")).to be_empty
    expect(response.body).not_to include(I18n.t("website.admin.pages.edit.add_section"))
    expect(response.body).not_to include(%(data-website-builder-target="handle"))
    expect(response.body).not_to include("lg:w-64 xl:w-72")
    expect(response.body).not_to include("aside.w-60")
    expect(response.body).to include(%(data-admin-page-workspace="true"))
    expect(response.body).to include(%(data-viewport="tablet"))
  end

  it "updates title and flags without slug while preserving the public URL and stored links" do
    site = create(:website, :published, customer: customer)
    home = create(:website_page, :home, :published, website: site, customer: customer, sections: [
      { "id" => "sec_cta", "type" => "cta_band", "props" => { "headline" => "Meet us", "button_label" => "About us", "button_href" => "about" } }
    ])
    page_record = create(:website_page, website: site, customer: customer, title: "About", slug: "about", nav_visible: true, published: false)
    original_links = home.sections.deep_dup

    patch "#{index_path}/pages/#{page_record.id}", params: {
      website_page: { title: "Our team", nav_visible: "0", published: "1", home: "0" }
    }, headers: { "X-Website-Composer" => "1", "Accept" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(page_record.reload).to have_attributes(title: "Our team", slug: "about", nav_visible: false, published: true, home: false)
    expect(home.reload.sections).to eq(original_links)

    get "/#{customer.id}/site"
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css("a[href='/#{customer.id}/about']").text).to include("About us")
    get "/#{customer.id}/site/about"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Our team")
  end

  it "saves the locked homepage without a slug parameter and keeps its root URL" do
    site = create(:website, :published, customer: customer)
    home = create(:website_page, :home, website: site, customer: customer)

    patch "#{index_path}/pages/#{home.id}", params: {
      website_page: { title: "Welcome", nav_visible: "1", published: "1", home: "1" }
    }

    expect(response).to have_http_status(:redirect)
    expect(home.reload).to have_attributes(title: "Welcome", slug: "", home: true, published: true)
    get "/#{customer.id}/site"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Welcome")
  end

  it "promotes an inner page to home without a slug parameter" do
    site = create(:website, customer: customer)
    home = create(:website_page, :home, website: site, customer: customer)
    page_record = create(:website_page, website: site, customer: customer, title: "About", slug: "about")

    patch "#{index_path}/pages/#{page_record.id}", params: {
      website_page: { title: "About", nav_visible: "1", published: "1", home: "1" }
    }

    expect(response).to have_http_status(:redirect)
    expect(page_record.reload).to have_attributes(slug: "", home: true)
    expect(home.reload.home).to be(false)
    expect(home.slug).to be_present
    expect(site.pages.where(home: true).pluck(:id)).to eq([page_record.id])
  end

  it "maps sections_json into saved sections on update" do
    skip "Website factory not available" unless website_records_available?

    Current.customer = customer
    site = create(:website, customer: customer)
    page_record = create(
      :website_page,
      website: site,
      customer: customer,
      title: "About",
      slug: "about",
      sections: [
        { "id" => "sec_quote", "type" => "quote", "props" => { "quote" => "Old", "attribution" => "Studio" } }
      ]
    )

    patch "#{index_path}/pages/#{page_record.id}", params: {
      website_page: {
        title: "About",
        slug: "about",
        sections_json: [
          { "id" => "sec_quote", "type" => "quote", "props" => { "quote" => "Make it beautiful.", "attribution" => "Studio" } }
        ].to_json
      }
    }

    expect(response).to have_http_status(:redirect)
    page_record.reload
    expect(page_record.sections.first["type"]).to eq("quote")
    expect(page_record.sections.first["props"]["quote"]).to eq("Make it beautiful.")
  end

  it "PATCH update with the composer header stays on the page as JSON" do
    skip "Website factory not available" unless website_records_available?

    Current.customer = customer
    site = create(:website, customer: customer)
    page_record = create(
      :website_page,
      website: site,
      customer: customer,
      title: "About",
      slug: "about",
      sections: [
        { "id" => "sec_quote", "type" => "quote", "props" => { "quote" => "Old" } }
      ]
    )

    patch "#{index_path}/pages/#{page_record.id}",
          params: {
            website_page: {
              title: "About",
              slug: "about",
              sections_json: [
                { "id" => "sec_quote", "type" => "quote", "props" => { "quote" => "Live." } }
              ].to_json
            }
          },
          headers: { "X-Website-Composer" => "1", "Accept" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("ok" => true)
    expect(page_record.reload.sections.first["props"]["quote"]).to eq("Live.")
  end

  it "PATCH update with the composer header returns JSON errors without redirecting" do
    skip "Website factory not available" unless website_records_available?

    Current.customer = customer
    site = create(:website, customer: customer)
    page_record = create(
      :website_page,
      website: site,
      customer: customer,
      title: "About",
      slug: "about",
      sections: [
        { "id" => "sec_quote", "type" => "quote", "props" => { "quote" => "Old" } }
      ]
    )

    patch "#{index_path}/pages/#{page_record.id}",
          params: { website_page: { title: "About", sections_json: "{bad" } },
          headers: { "X-Website-Composer" => "1", "Accept" => "application/json" }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["ok"]).to eq(false)
    expect(page_record.reload.sections.first["props"]["quote"]).to eq("Old")
  end

  it "preserves secondary fields and inactive sections when saving copy from the composer" do
    site = create(:website, customer: customer)
    page_record = create(:website_page, website: site, customer: customer, sections: [
      {
        "id" => "sec_hero", "type" => "hero_cinematic",
        "props" => {
          "headline" => "Original", "primary_label" => "Learn more", "primary_href" => "about",
          "image_url" => "https://cdn.example/hero.jpg", "tone" => "dark"
        }
      },
      {
        "id" => "sec_cards", "type" => "card_grid",
        "props" => { "heading" => "Team", "cards" => [{ "title" => "People", "body" => "Our story", "href" => "about", "image_url" => "https://cdn.example/team.jpg" }] }
      }
    ])
    original = page_record.reload.sections.deep_dup
    draft = original.deep_dup
    draft.first["props"]["headline"] = "Edited copy"

    patch "#{index_path}/pages/#{page_record.id}",
          params: { website_page: { title: page_record.title, slug: page_record.slug, sections_json: draft.to_json } },
          headers: { "X-Website-Composer" => "1", "Accept" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("ok" => true)
    expect(page_record.reload.sections).to eq(draft)
    expect(page_record.sections.last).to eq(original.last)
    expect(page_record.sections.first["props"].except("headline")).to eq(original.first["props"].except("headline"))
  end

  it "POST preview overlays draft copy without writing the page" do
    skip "Website factory not available" unless website_records_available?

    Current.customer = customer
    site = create(:website, customer: customer)
    page_record = create(
      :website_page,
      website: site,
      customer: customer,
      title: "About",
      slug: "about",
      sections: [
        { "id" => "sec_quote", "type" => "quote", "props" => { "quote" => "Saved quote" } }
      ]
    )

    post "#{index_path}/pages/#{page_record.id}/preview", params: {
      embed: 1,
      website_page: {
        title: "Draft title",
        slug: "about",
        sections_json: [
          { "id" => "sec_quote", "type" => "quote", "props" => { "quote" => "Unsaved quote" } }
        ].to_json
      }
    }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Unsaved quote")
    expect(response.body).to include("Draft title")
    expect(page_record.reload.title).to eq("About")
    expect(page_record.sections.first["props"]["quote"]).to eq("Saved quote")
  end

  describe "page theme and section styles" do
    let(:site) { create(:website, customer: customer) }
    let(:page_record) do
      create(:website_page, website: site, customer: customer, title: "About", slug: "about",
                            sections: [{ "id" => "sec_quote", "type" => "quote", "props" => { "quote" => "Saved quote" } }])
    end
    let(:styled_sections) do
      [{ "id" => "sec_quote", "type" => "quote", "props" => { "quote" => "Saved quote", "styles" => { "section" => { "background" => "#123abc" } } } }]
    end

    it "saves a page theme override and section styles from the composer" do
      patch "#{index_path}/pages/#{page_record.id}",
            params: { website_page: { title: "About", theme_key: "midnight", sections_json: styled_sections.to_json } },
            headers: { "X-Website-Composer" => "1", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      page_record.reload
      expect(page_record.theme_key).to eq("midnight")
      expect(page_record.sections.first.dig("props", "styles")).to eq("section" => { "background" => "#123abc" })
    end

    it "rejects an unknown theme override" do
      patch "#{index_path}/pages/#{page_record.id}",
            params: { website_page: { title: "About", theme_key: "neon" } },
            headers: { "X-Website-Composer" => "1", "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(page_record.reload.theme_key).to be_nil
    end

    it "previews the draft theme and styles without saving them" do
      post "#{index_path}/pages/#{page_record.id}/preview", params: {
        embed: 1, website_page: { title: "About", theme_key: "midnight", sections_json: styled_sections.to_json }
      }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ERB::Util.html_escape(Websites::ThemePresets.theme("midnight").root_style))
      expect(response.body).to include("background-color: #123abc;")
      expect(page_record.reload.theme_key).to be_nil
    end
  end

  it "POST preview ignores invalid sections JSON" do
    skip "Website factory not available" unless website_records_available?

    Current.customer = customer
    site = create(:website, customer: customer)
    page_record = create(
      :website_page,
      website: site,
      customer: customer,
      title: "About",
      slug: "about",
      sections: [
        { "id" => "sec_quote", "type" => "quote", "props" => { "quote" => "Saved quote" } }
      ]
    )

    post "#{index_path}/pages/#{page_record.id}/preview", params: {
      embed: 1,
      website_page: { title: "Draft title", sections_json: "{not-json" }
    }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Saved quote")
    expect(page_record.reload.sections.first["props"]["quote"]).to eq("Saved quote")
  end

  it "creates a page from identity fields without requiring slug or home" do
    skip "Website factory not available" unless website_records_available?

    Current.customer = customer
    site = create(:website, :published, customer: customer)
    home = create(:website_page, :home, website: site, customer: customer)

    expect {
      post "#{index_path}/pages", params: {
        website_page: {
          title: "About",
          nav_visible: "1",
          published: "1",
          sections_json: "[]"
        }
      }
    }.to change { WebsitePage.where(customer_id: customer.id).count }.by(1)

    created = WebsitePage.find_by!(customer_id: customer.id, slug: "about")
    expect(created).to have_attributes(
      title: "About",
      slug: "about",
      home: false,
      website_id: site.id,
      customer_id: customer.id
    )
    expect(home.reload.home).to be(true)
    expect(response).to have_http_status(:redirect)
    expect(response).to redirect_to(edit_admin_modules_website_page_path(customer.id, created))
    expect(flash[:notice]).to eq(I18n.t("website.admin.flash.page_created"))
    get "/#{customer.id}/site/#{created.slug}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("About")
  end

  it "creates a page when slug is left blank by generating it from the title" do
    skip "Website factory not available" unless website_records_available?

    Current.customer = customer
    site = create(:website, customer: customer)
    create(:website_page, :home, website: site, customer: customer)

    expect {
      post "#{index_path}/pages", params: {
        website_page: {
          title: "Our Journal",
          slug: "",
          nav_visible: "1",
          published: "0",
          sections_json: "[]"
        }
      }
    }.to change { WebsitePage.where(customer_id: customer.id).count }.by(1)

    created = WebsitePage.find_by!(customer_id: customer.id, slug: "our-journal")
    expect(created.title).to eq("Our Journal")
    expect(response).to redirect_to(edit_admin_modules_website_page_path(customer.id, created))
  end

  it "re-renders new with errors when the slug is already taken" do
    skip "Website factory not available" unless website_records_available?

    Current.customer = customer
    site = create(:website, customer: customer)
    create(:website_page, :home, website: site, customer: customer)
    create(:website_page, website: site, customer: customer, title: "About", slug: "about")

    expect {
      post "#{index_path}/pages", params: {
        website_page: {
          title: "About copy",
          slug: "about",
          nav_visible: "1",
          published: "0",
          sections_json: "[]"
        }
      }
    }.not_to change { WebsitePage.where(customer_id: customer.id).count }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include(I18n.t("website.errors.slug_taken"))
  end

  it "does not create a page for another tenant" do
    skip "Website factory not available" unless website_records_available?

    Current.customer = customer
    create(:website, customer: customer)

    other = create(:customer)
    enable_module!("website", other, name: "Website")
    Current.customer = other
    other_site = create(:website, customer: other)
    Current.customer = customer
    sign_in create(:user, :admin, customer: other)

    expect {
      post "#{index_path}/pages", params: {
        website_page: { title: "Leak", slug: "leak" }
      }
    }.not_to change { WebsitePage.where(website_id: other_site.id).count }

    expect(response).to have_http_status(:not_found)
      .or have_http_status(:forbidden)
      .or have_http_status(:found)
    expect(WebsitePage.find_by(customer_id: customer.id, slug: "leak")).to be_nil
  end

end
