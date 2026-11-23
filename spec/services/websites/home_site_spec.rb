# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::HomeSite do
  def source(locale = :en)
    described_class.definition(locale: locale)
  end

  def page_source(key, locale = :en)
    source(locale).fetch("pages").find { |page| page["slug"] == (key == "home" ? "" : key) }
  end

  def plan_props(locale = :en)
    page_source("pricing", locale).fetch("sections").find { |section| section["type"] == "pricing" }.fetch("props")
  end

  def assets
    Rails.root.glob("public/site-images/anysys/*.svg")
  end

  def photos
    Rails.root.glob("public/site-images/anysys/*.webp")
  end

  def photo(name) = "/site-images/anysys/anysys-photo-#{name}.webp"

  def image_urls(value)
    case value
    when Hash then value.flat_map { |key, item| key == "image_url" ? [item] : image_urls(item) }
    when Array then value.flat_map { |item| image_urls(item) }
    else []
    end
  end

  describe ".definition" do
    it "composes the five-page marketing map with stable role ids and photo-led About and Contact heroes" do
      pages = source.fetch("pages")
      expect(pages.map { |page| page["sections"].size }).to eq([11, 9, 5, 6, 3])
      expect(pages.map { |page| page["slug"] }).to eq(["", "platform", "pricing", "about", "contact"])
      expect(pages.map { |page| page["sections"].pluck("type") }).to eq([
        %w[hero_centered proof_strip logo_cloud ai_preview feature_grid card_grid feature_grid split_image_text steps faq cta_band],
        %w[hero_centered ai_preview feature_grid card_grid feature_grid split_image_text comparison_table steps cta_band],
        %w[hero_centered pricing feature_grid faq cta_band],
        %w[hero_centered proof_strip rich_text feature_grid split_image_text cta_band],
        %w[hero_centered rich_text cta_band]
      ])
      expect(pages.map { |page| page["sections"].pluck("id") }).to eq([
        %w[hero stats industries preview assistant desktop capabilities website steps faq cta].map { |role| "home_site_home_#{role}" },
        %w[hero preview assistant desktop capabilities website comparison steps cta].map { |role| "home_site_platform_#{role}" },
        %w[hero plans foundation faq cta].map { |role| "home_site_pricing_#{role}" },
        %w[hero stats mission principles craft cta].map { |role| "home_site_about_#{role}" },
        %w[hero availability cta].map { |role| "home_site_contact_#{role}" }
      ])
      pages.each do |page|
        hero = page["sections"].first
        expect(hero["type"]).to eq("hero_centered")
        if %w[about contact].include?(page["slug"])
          expect(hero["props"]).to include("media_mode" => "image", "image_url" => photo(page["slug"] == "about" ? "about-team" : "contact"))
        else
          expect(hero["props"]).to include("media_mode" => "none")
          expect(hero["props"]).not_to have_key("image_url")
        end
        ids = page["sections"].pluck("id")
        expect(ids.uniq.size).to eq(ids.size)
        expect(ids).to all(be_present)
      end
      expect(source).to eq(source)
    end

    it "adds capability-only foundation copy after plans with titled bilingual items" do
      {
        en: ["More than a plan. A complete, connected workspace.", "Included in every plan", ["AI assistant", "Records, forms & websites", "Members, payments & messaging"]],
        "zh-CN": ["不止一个方案，更是完整贯通的工作空间。", "所有方案均包含", %w[AI\ 助手 记录、表单与网站 会员、支付与消息]]
      }.each do |locale, (heading, kicker, titles)|
        foundation = page_source("pricing", locale).fetch("sections")[2]
        expect(foundation).to include("id" => "home_site_pricing_foundation", "type" => "feature_grid")
        props = foundation.fetch("props")
        expect(props).to include("heading" => heading, "kicker" => kicker)
        expect(props["subhead"]).to be_present
        expect(props.fetch("items").pluck("title")).to eq(titles)
        expect(props.fetch("items").map(&:keys)).to all(match_array(%w[title body]))
        expect(image_urls(props)).to be_empty
        expect(props.to_json).not_to match(/\$|14-day|14 天|unlimited|不限/i)
      end
      expect(page_source("pricing")["sections"][2].dig("props", "items").pluck("body")).to all(be_present)
    end

    it "gives About a team-photo hero and a photo-led craft story" do
      { en: "We build tools for\npeople who build.", "zh-CN": "我们为创造者，\n打造创造的工具。" }.each do |locale, headline|
        sections = page_source("about", locale).fetch("sections")
        expect(sections.first.dig("props", "headline")).to eq(headline)
        expect(image_urls(sections.first)).to eq([photo("about-team")])
        craft = sections.find { |section| section["id"] == "home_site_about_craft" }
        expect(craft["type"]).to eq("split_image_text")
        expect(craft.fetch("props")).to include("image_url" => photo("craft"), "image_side" => "left")
        expect(craft.fetch("props").keys).to match_array(%w[heading body image_url image_side])
        expect(image_urls(sections.drop(1))).to eq([photo("craft")])
      end
    end

    it "provides Contact route descriptions at request locale without persisting new props" do
      {
        en: ["See how records, forms and websites work together.", "Compare plans and find the perfect fit.", "Create a workspace and start shaping your idea."],
        "zh-CN": ["了解记录、表单与网站如何相互贯通。", "比较各个方案，找到最合适的选择。", "创建工作空间，让构想开始落地。"]
      }.each do |locale, descriptions|
        I18n.with_locale(locale) do
          expect(%w[platform pricing workspace].map { |route| I18n.t("website.home_site.contact.routes.#{route}", raise: true) }).to eq(descriptions)
        end
        expect(page_source("contact", locale).to_json).not_to include(*descriptions)
      end
    end

    it "assigns eleven bundled photos from six assets while retaining the complete SVG overlay inventory" do
      english = image_urls(source)
      chinese = image_urls(source(:"zh-CN"))

      expect(english.size).to eq(11)
      expect(chinese).to eq(english)
      desktop = photo("desktop-night")
      expect(source["pages"].map { |page| image_urls(page) }).to eq([
        [*Array.new(3, desktop), photo("studio-owner")], [*Array.new(3, desktop), photo("team-collab")], [],
        [photo("about-team"), photo("craft")], [photo("contact")]
      ])
      expect(english).to all(match(Websites::Href::BUNDLED_PHOTO_PATH))
      expect(english).to all(satisfy { |url| Websites::Href.media?(url) })
      %i[en zh-CN].each { |locale| expect(source(locale).to_json).not_to include("placeholder") }
      photo_inventory = photos.map { |path| "/#{path.relative_path_from(Rails.root.join('public'))}" }
      expect(photo_inventory).to match_array(english.uniq)
      photos.each { |path| expect(File.binread(path, 12)).to start_with("RIFF").and(end_with("WEBP")) }
      expect(assets.size).to eq(15)
      inventory = assets.map { |path| "/#{path.relative_path_from(Rails.root.join('public'))}" }
      expect(Websites::IllustrationComponent::ILLUSTRATIONS.keys).to match_array(inventory)
      %i[en zh-CN].each do |locale|
        Websites::IllustrationComponent::ILLUSTRATIONS.each_value do |scene|
          scene.fetch(:labels).each { |label| expect(I18n.t(label.fetch(:key), locale: locale, raise: true)).to be_present }
        end
      end
      expect(assets + photos).to all(be_file)
    end

    it "ships self-contained vector artwork without scripts, embedded text or external resources" do
      allowed_elements = %w[svg defs g path rect circle ellipse line polyline polygon linearGradient radialGradient stop clipPath mask filter feDropShadow feGaussianBlur use]

      assets.each do |path|
        aggregate_failures(path.to_s) do
          svg = Nokogiri::XML(File.read(path)) { |config| config.strict.nonet }
          expect(svg.root.name).to eq("svg")
          expect(svg.root.namespace.href).to eq("http://www.w3.org/2000/svg")
          expect(svg.root["viewBox"].split.map(&:to_f)).to match([0, 0, be > 0, be > 0])
          expect(svg.internal_subset).to be_nil
          expect(svg.xpath("//processing-instruction() | //text()[normalize-space(.) != '']")).to be_empty
          expect(svg.xpath("//*").map(&:name).uniq - allowed_elements).to be_empty
          expect(svg.xpath("//*[local-name()='path' or local-name()='rect' or local-name()='circle']")).not_to be_empty

          attributes = svg.xpath("//*").flat_map(&:attribute_nodes)
          expect(attributes.map(&:name)).not_to include("style")
          expect(attributes.map(&:name).grep(/\Aon/i)).to be_empty
          references = attributes.select { |attribute| attribute.name == "href" }.map(&:value) +
                       attributes.flat_map { |attribute| attribute.value.scan(/url\((.*?)\)/i).flatten.map { |value| value.delete("\"'").strip } }
          expect(references).to all(match(/\A#[a-zA-Z][\w.-]*\z/))
          ids = svg.xpath("//*[@id]").map { |node| "##{node['id']}" }
          expect(references - ids).to be_empty
        end
      end
    end

    it "translates at call time without changing global locale or sharing mutable definitions" do
      I18n.with_locale(:"zh-CN") do
        expect(source.dig("pages", 0, "title")).to eq("Home")
        expect(source(:"zh-CN").dig("pages", 0, "title")).to eq("首页")
        expect(I18n.locale).to eq(:"zh-CN")
      end
      source["pages"].first["sections"].clear
      expect(source.dig("pages", 0, "sections").size).to eq(11)
    end

    it "keeps the deliberate bilingual line breaks, compact draft outlines and hero actions" do
      { en: "Describe your business.\nAI builds the rest.", "zh-CN": "说出你的业务，\n其余交给 AI。" }.each do |locale, headline|
        expect(page_source("home", locale).dig("sections", 0, "props", "headline")).to eq(headline)
        %w[home platform about contact].each do |key|
          expect(page_source(key, locale).dig("sections", 0, "props", "headline").lines.size).to eq(2)
        end
        %w[home platform about].each do |key|
          hero = page_source(key, locale).dig("sections", 0, "props")
          expect(hero).to include("primary_href" => "/auth/sign_up", "secondary_href" => (key == "platform" ? "pricing" : "platform"))
        end
        %w[home platform].each do |key|
          preview = page_source(key, locale)["sections"].find { |section| section["type"] == "ai_preview" }.fetch("props")
          expect(preview.values_at("kicker", "subhead")).to all(be_present)
          expect(preview["items"].map { |item| item.fetch("body").lines.size }).to eq([2, 2, 2])
          expect(preview["items"].flat_map(&:keys).uniq).to match_array(%w[title body status])
        end
        %w[pricing contact].each do |key|
          hero = page_source(key, locale).dig("sections", 0, "props")
          expect(hero.values_at("primary_label", "primary_href", "secondary_label", "secondary_href")).to eq(["", "", "", ""])
        end
        mission = page_source("about", locale)["sections"].find { |section| section["type"] == "rich_text" }
        expect(mission.dig("props", "body").split("\n\n").size).to eq(2)
      end
    end

    it "uses image-free indexes and process entries with one shared stock-proof Windows panel" do
      %i[en zh-CN].each do |locale|
        sections = source(locale)["pages"].flat_map { |page| page["sections"] }
        indexes = sections.select { |section| %w[feature_grid steps].include?(section["type"]) }
        expect(image_urls(indexes)).to be_empty
        expect(indexes.map { |section| section.dig("props", "items").size }).to eq([6, 6, 3, 6, 6, 3, 3, 3])
        expect(indexes.flat_map { |section| section.dig("props", "items") }).to all(include("title", "body"))
        steps = indexes.select { |section| section["type"] == "steps" }
        expect(steps.first.dig("props", "items")).to eq(steps.last.dig("props", "items"))
        panels = sections.select { |section| section["type"] == "card_grid" }.pluck("props")
        expect(panels.first).to eq(panels.last)
        expect(panels.first["cards"]).to all(include("image_url" => photo("desktop-night"), "href" => ""))
        expect(image_urls(Websites::Media.fill_sections(sections))).to eq(image_urls(sections))
      end
    end

    it "keeps every authored source prop available through existing composer fields" do
      check_fields = lambda do |props, fields|
        expect(props.keys - fields.pluck(:key)).to be_empty
        fields.select { |field| field[:kind] == :array }.each do |field|
          Array(props[field[:key]]).each { |item| check_fields.call(item, field.fetch(:item_fields)) }
        end
      end
      source["pages"].flat_map { |page| page["sections"] }.each do |section|
        expect(Websites::SectionKit.known?(section["type"])).to be(true)
        check_fields.call(section.fetch("props"), Websites::SectionFields.schema_for(section["type"]))
      end
    end

    it "uses the exact reusable preview props and labels every outcome as a draft" do
      %w[home platform].each do |page|
        props = page_source(page)["sections"].find { |section| section["type"] == "ai_preview" }.fetch("props")
        expect(props.keys).to match_array(%w[kicker heading subhead example_label prompt_label prompt review_note output_label items])
        expect(props["items"].size).to eq(3)
        expect(props["items"]).to all(include("title", "body", "status" => "Draft"))
      end
    end

    it "provides four catalog-backed USD plans only on Pricing with Starter as most popular and honest limits" do
      pricing = plan_props
      expect(source["pages"].select { |page| page["sections"].any? { |section| section["type"] == "pricing" } }.pluck("slug")).to eq(["pricing"])
      expect(pricing["tiers"].pluck("name")).to eq(%w[Free Starter Pro Enterprise])
      expect(pricing["tiers"].pluck("price")).to eq(%w[$0 $29 $99 $499])
      expect(pricing["tiers"].pluck("cadence").uniq).to eq(["USD / month"])
      expect(pricing["tiers"].select { |tier| tier["highlight"] == "featured" }.pluck("name")).to eq(["Starter"])
      expect(pricing["featured_label"]).to eq("Most popular")
      expect(pricing["tiers"].first["features"]).to eq("Up to 10 pages\nUp to 5 custom record types\n1 member seat")
      expect(pricing["tiers"][1]["features"]).to eq("Up to 50 pages\nUp to 25 custom record types\n5 member seats\n14-day free trial")
      expect(pricing["tiers"][2]["features"]).to eq("Up to 500 pages\nUp to 200 custom record types\n25 member seats\n14-day free trial")
      expect(pricing["tiers"].last["features"]).to eq("Unlimited pages\nUnlimited custom record types\nUnlimited member seats\n14-day free trial")
      expect(pricing["tiers"].pluck("button_href").uniq).to eq(["/auth/sign_up"])
      %i[en zh-CN].each do |locale|
        tiers = page_source("pricing", locale).fetch("sections").find { |section| section["type"] == "pricing" }.dig("props", "tiers")
        expect(tiers.pluck("button_label").uniq).to eq([I18n.t("website.home_site.actions.start", locale: locale)])
      end
      expect(page_source("pricing").to_json).to include("not the marketing pages", "including administrators")
    end

    it "derives prices, quotas and trials from the reference catalog without reading or seeding live offers" do
      catalog = Billing::StandardPlans::CATALOG.deep_dup
      catalog[1].merge!(amount_usd: 37, trial_days: 9)
      catalog[1][:limits].merge!("page" => 72, "entity" => 33, "member" => 8)
      stub_const("Billing::StandardPlans::CATALOG", catalog)
      expect(Billing::StandardPlans).not_to receive(:seed!)
      expect(Billing::Plan).not_to receive(:all)
      expect(Billing::Plan).not_to receive(:where)
      %i[en zh-CN].each do |locale|
        tier = plan_props(locale)["tiers"][1]
        expect(tier["price"]).to eq("$37")
        expect(tier["features"].split("\n").map { |line| line[/\d+/].to_i }).to eq([72, 33, 8, 9])
      end
    end

    it "qualifies reference USD pricing visibly above the cards and retains detailed quota and trial FAQ" do
      {
        en: ["Reference monthly prices in USD", "In the standard plan guide,", "not the marketing pages", "including administrators", "usage charges"],
        "zh-CN": ["美元月度参考价格", "按标准方案说明，", "不含网站构建器中的营销页面", "包括管理员", "用量费用"]
      }.each do |locale, (reference, qualification, pages, seats, usage)|
        sections = page_source("pricing", locale).fetch("sections")
        expect(sections.first.dig("props", "subhead")).to include(reference)
        expect(plan_props(locale).values_at("kicker", "subhead")).to eq(["", ""])
        answers = sections.find { |section| section["type"] == "faq" }.dig("props", "items").pluck("answer")
        expect(answers.size).to eq(4)
        expect(answers.first(2)).to all(start_with(qualification))
        expect(answers[2]).to include(pages, seats)
        expect(answers[3]).to include(usage)
      end
    end

    it "has no stock photos, testimonials, downloads or unverified contact links in either locale" do
      %i[en zh-CN].each do |locale|
        definition = source(locale)
        blob = definition.to_json
        expect(blob).not_to match(/unsplash|download\/desktop|example\.com|mailto:|testimonials|flowchart|multi-tenant|annual|priority support/i)
        expect(blob).to include("/auth/sign_up", "Windows", locale == :en ? "Coming soon" : "即将推出")
        expect(definition["footer"]["columns"].last["links"].first["url"]).to eq("platform")
        expect(page_source("contact", locale)["sections"].map { |section| section["type"] }).to eq(%w[hero_centered rich_text cta_band])
      end
    end

    it "keeps locale leaf keys and interpolation variables in parity, including array items" do
      flatten = lambda do |value, path = []|
        case value
        when Hash then value.flat_map { |key, item| flatten.call(item, path + [key.to_s]) }
        when Array then value.each_with_index.flat_map { |item, index| flatten.call(item, path + [index.to_s]) }
        else [[path.join("."), value.to_s.scan(/%\{([^}]+)\}/).flatten.sort]]
        end
      end
      catalogs = %w[en zh-CN].map do |locale|
        YAML.safe_load_file(Rails.root.join("config/locales/website_home_site.#{locale}.yml")).fetch(locale).dig("website", "home_site")
      end
      expect(flatten.call(catalogs.first).to_h).to eq(flatten.call(catalogs.last).to_h)
      expect(flatten.call(source).to_h).to eq(flatten.call(source(:"zh-CN")).to_h)
    end
  end

  describe ".apply!" do
    let!(:customer) { create(:customer, id: described_class::CUSTOMER_ID) }
    let!(:website_module) do
      FeatureModules::Module.find_by(key: "website")&.tap { |mod| mod.update!(status: :active) } ||
        create(:feature_module, key: "website")
    end

    after { Current.reset }

    it "restores a missing site directly, enables only its assignment, and publishes all five pages" do
      expect(Websites::Skeletons).not_to receive(:apply!)
      site = described_class.apply!
      expect(site).to be_published
      expect(site.theme).to eq(described_class::THEME)
      expect(site.pages.map { |page| page.sections.size }).to eq([11, 9, 5, 6, 3])
      expect(site.pages).to all(be_published.and(be_nav_visible))
      expect(site.pages.pluck(:customer_id).uniq).to eq([customer.id])
      expect(site.pages.flat_map(&:sections).to_json).not_to include("unsplash")
      expect(site.pages.map(&:sections)).to eq(source["pages"].pluck("sections"))
      expect(image_urls(site.pages.flat_map(&:sections)).size).to eq(11)
      expect(FeatureModules::Website::Registration.enabled_for?(customer.id)).to be(true)
    end

    it "restores source edits in place with stable site, page and section identifiers" do
      site = described_class.apply!
      page_ids = site.pages.pluck(:id)
      section_ids = site.pages.map { |page| page.sections.pluck("id") }
      home = site.home_page
      home.update!(title: "Owner title", sections: home.sections.map { |section| section.deep_merge("props" => { "headline" => "Owner wording" }) })

      expect { described_class.apply! }.not_to change(WebsitePage, :count)
      expect(site.reload.pages.pluck(:id)).to eq(page_ids)
      expect(site.pages.map { |page| page.sections.pluck("id") }).to eq(section_ids)
      expect(site.home_page.title).to eq("Home")
      expect(site.home_page.sections.first.dig("props", "headline")).to eq(source.dig("pages", 0, "sections", 0, "props", "headline"))
    end

    it "upgrades the previous composition while retaining pricing IDs, craft identity, layouts and media budget" do
      site = described_class.apply!
      site.update!(default_layout_key: "saas_home")
      pricing = site.pages.find_by!(slug: "pricing")
      old_pricing = pricing.sections.reject { |section| section["id"] == "home_site_pricing_foundation" }
      old_pricing.each_with_index { |section, index| section["id"] = "sec_pricing_#{index}" }
      pricing.update!(sections: old_pricing)
      about = site.pages.find_by!(slug: "about")
      old_about = about.sections.deep_dup
      old_about.first["props"].delete("image_url")
      old_about.first["props"]["media_mode"] = "none"
      craft = old_about.find { |section| section["id"] == "home_site_about_craft" }
      craft["type"] = "rich_text"
      craft["props"] = craft["props"].except("image_url", "image_side")
      about.update!(sections: old_about, layout_key: "presence_about")
      identities = site.pages.pluck(:id, :layout_key)
      site_layouts = site.attributes.slice("skeleton_key", "default_layout_key")

      restored = described_class.apply!
      expect(restored.id).to eq(site.id)
      expect(restored.attributes.slice("skeleton_key", "default_layout_key")).to eq(site_layouts)
      expect(restored.pages.pluck(:id, :layout_key)).to eq(identities)
      expect(pricing.reload.sections.pluck("id")).to eq(["sec_pricing_0", "sec_pricing_1", "home_site_pricing_foundation", "sec_pricing_2", "sec_pricing_3"])
      expect(about.reload.sections.pluck("id")).to eq(old_about.pluck("id"))
      expect(about.sections.find { |section| section["id"] == craft["id"] }).to include("type" => "split_image_text")
      expect(about.sections.find { |section| section["id"] == craft["id"] }["props"]).to include("image_url" => photo("craft"))
      expect(image_urls(about.sections.first)).to eq([photo("about-team")])
      expect(image_urls(restored.pages.flat_map(&:sections)).size).to eq(11)
      ids = restored.pages.map { |page| page.sections.pluck("id") }
      described_class.apply!
      expect(restored.pages.reload.map { |page| page.sections.pluck("id") }).to eq(ids)
    end

    it "retains changed-type semantic roles instead of borrowing a removed same-type source role" do
      site = create(:website, customer: customer)
      page = create(:website_page, :home, website: site, sections: [
        { "id" => "home_site_home_ai_builder", "type" => "split_image_text", "props" => {} },
        { "id" => "home_site_home_website", "type" => "bento_grid", "props" => {} },
        { "id" => "home_site_home_hero", "type" => "hero_cinematic", "props" => { "headline" => "Old heading" } },
        { "id" => "home_site_home_plans", "type" => "pricing", "props" => {} }
      ])
      about = create(:website_page, website: site, slug: "about", sections: [
        { "id" => "home_site_about_mission", "type" => "split_image_text", "props" => {} },
        { "id" => "home_site_about_principles", "type" => "bento_grid", "props" => {} },
        { "id" => "home_site_about_other", "type" => "split_image_text", "props" => {} }
      ])
      described_class.apply!
      expect(page.reload.sections.first).to include("id" => "home_site_home_hero", "type" => "hero_centered")
      expect(page.sections.find { |section| section["type"] == "split_image_text" }).to include("id" => "home_site_home_website")
      expect(page.sections.pluck("id")).not_to include("home_site_home_ai_builder", "home_site_home_plans")
      expect(about.reload.sections.find { |section| section["type"] == "feature_grid" }).to include("id" => "home_site_about_principles")
      expect(about.sections.find { |section| section["type"] == "rich_text" }).to include("id" => "home_site_about_mission")
      expect(about.sections.find { |section| section["id"] == "home_site_about_craft" }).to include("type" => "split_image_text")
      ids = site.pages.reload.map { |item| item.sections.pluck("id") }
      described_class.apply!
      expect(site.pages.reload.map { |item| item.sections.pluck("id") }).to eq(ids)
      expect(ids).to all(satisfy { |list| list.uniq == list })
    end

    it "uses unambiguous opaque legacy types for surviving changed-type roles" do
      site = create(:website, customer: customer)
      home = create(:website_page, :home, website: site, sections: [
        { "id" => "existing-website", "type" => "bento_grid", "props" => {} },
        { "id" => "existing-hero", "type" => "hero_cinematic", "props" => {} },
        { "id" => "existing-pricing", "type" => "pricing", "props" => {} }
      ])
      platform = create(:website_page, website: site, slug: "platform", sections: [
        { "id" => "existing-capabilities", "type" => "bento_grid", "props" => {} },
        { "id" => "existing-process", "type" => "alternating_features", "props" => {} }
      ])
      described_class.apply!
      expect(home.reload.sections.first["id"]).to eq("existing-hero")
      expect(home.sections.find { |section| section["type"] == "split_image_text" }["id"]).to eq("existing-website")
      expect(home.sections.pluck("id")).not_to include("existing-pricing")
      expect(platform.reload.sections.find { |section| section["id"] == "existing-capabilities" }).to include("type" => "feature_grid")
      expect(platform.sections.pluck("id")).to include("home_site_platform_assistant")
      expect(platform.sections.find { |section| section["type"] == "steps" }["id"]).to eq("existing-process")
      before = site.pages.reload.map { |page| page.sections.pluck("id") }
      described_class.apply!
      expect(site.pages.reload.map { |page| page.sections.pluck("id") }).to eq(before)
    end

    it "retains an unambiguous opaque craft predecessor after reserving the other About roles" do
      sections = page_source("about").fetch("sections").deep_dup
      craft = sections.find { |section| section["id"] == "home_site_about_craft" }
      craft.merge!("id" => "legacy-about-craft", "type" => "rich_text")
      site = create(:website, customer: customer)
      about = create(:website_page, website: site, slug: "about", sections: sections)
      described_class.apply!
      expect(about.reload.sections[4]).to include("id" => "legacy-about-craft", "type" => "split_image_text")
    end

    it "reserves exact ids before opaque type fallback and does not infer roles from arbitrary suffixes" do
      site = create(:website, customer: customer)
      about = create(:website_page, website: site, slug: "about", sections: [
        { "id" => "owner_hero", "type" => "rich_text", "props" => {} },
        { "id" => "home_site_about_cta", "type" => "rich_text", "props" => {} },
        { "id" => "home_site_home_mission", "type" => "split_image_text", "props" => {} }
      ])
      described_class.apply!
      expect(about.reload.sections.first["id"]).to eq("home_site_about_hero")
      expect(about.sections.find { |section| section["type"] == "rich_text" }["id"]).to eq("home_site_about_mission")
      expect(about.sections.last["id"]).to eq("home_site_about_cta")
      expect(about.sections.find { |section| section["id"] == "home_site_about_craft" }).to include("type" => "split_image_text")
      expect(about.sections.pluck("id")).not_to include("owner_hero", "home_site_home_mission")
    end

    it "leaves ambiguous opaque type mappings on stable source ids and consumes duplicate predecessors once" do
      site = create(:website, customer: customer)
      page = create(:website_page, :home, website: site, sections: [
        { "id" => "duplicate", "type" => "hero_centered", "props" => {} },
        { "id" => "duplicate", "type" => "card_grid", "props" => {} },
        { "id" => "first-feature", "type" => "feature_grid", "props" => {} },
        { "id" => "second-feature", "type" => "feature_grid", "props" => {} }
      ])
      described_class.apply!
      expect(page.reload.sections.select { |section| section["type"] == "feature_grid" }.pluck("id")).to eq(%w[home_site_home_assistant home_site_home_capabilities])
      ids = page.sections.pluck("id")
      expect(ids.count("duplicate")).to eq(1)
      expect(ids.uniq).to eq(ids)
      described_class.apply!
      expect(page.reload.sections.pluck("id")).to eq(ids)
    end

    it "recreates missing pages without duplicating surviving pages" do
      site = described_class.apply!
      surviving = site.pages.find_by!(slug: "platform")
      site.pages.where.not(id: surviving.id).destroy_all
      described_class.apply!
      expect(site.pages.reload.size).to eq(5)
      expect(site.pages.find_by!(slug: "platform").id).to eq(surviving.id)
      expect(site.home_page).to be_present
    end

    it "preserves unrelated pages including their content, publication and position" do
      site = described_class.apply!
      extra = create(:website_page, website: site, title: "Campaign", slug: "campaign", position: 2,
                     published: false, nav_visible: false, sections: [{ "id" => "owner-copy", "type" => "rich_text", "props" => { "body" => "Keep me" } }])
      attributes = extra.attributes
      described_class.apply!
      expect(extra.reload.attributes).to eq(attributes)
      expect(site.pages.reload.size).to eq(6)
    end

    it "preserves uploaded media blobs while explicitly restoring source image assignments" do
      site = described_class.apply!
      blob = ActiveStorage::Blob.create_before_direct_upload!(
        filename: "owner.png", byte_size: 1, checksum: Base64.strict_encode64(Digest::MD5.digest("x")),
        content_type: "image/png", metadata: { "customer_id" => customer.id }
      )
      before_blob = blob.attributes
      page = site.home_page
      sections = page.sections.deep_dup
      sections.find { |section| section["type"] == "split_image_text" }["props"]["image_url"] = "/#{customer.id}/site/media/#{blob.signed_id}"
      page.update!(sections: sections)

      restored = described_class.apply!
      expect(restored.id).to eq(site.id)
      expect(blob.reload.attributes).to eq(before_blob)
      expect(image_urls(page.reload.sections)).to eq(image_urls(page_source("home")))
    end

    it "persists the selected source language as editable strings; locale changes do not rewrite it" do
      site = described_class.apply!(locale: :"zh-CN")
      expect(site.home_page.title).to eq("首页")
      expect(site.seo).to eq(source(:"zh-CN")["seo"])
      expect(site.footer).to eq(source(:"zh-CN")["footer"])
      page = site.home_page
      props = page.sections.deep_dup
      props.first["props"]["headline"] = "Owner's wording"
      result = Websites::Activities::SavePage.call(page: page, params: { sections: props })
      expect(result).to be_success
      I18n.with_locale(:en) do
        expect(page.reload.title).to eq("首页")
        expect(page.sections.first.dig("props", "headline")).to eq("Owner's wording")
      end
    end

    it "is locked to the platform customer even with another Current.customer" do
      other = create(:customer)
      other_site = create(:website, customer: other)
      other_page = create(:website_page, :home, website: other_site)
      original = [other_site.attributes, other_page.attributes]
      Current.customer = other
      expect { described_class.apply!(customer_id: other.id) }.to raise_error(ArgumentError)
      site = described_class.apply!
      expect(site.customer_id).to eq(customer.id)
      expect([other_site.reload.attributes, other_page.reload.attributes]).to eq(original)
      expect(FeatureModules::Website::Registration.enabled_for?(other.id)).to be(false)
      expect(Current.customer).to eq(other)
    end

    it "fails without changing a globally inactive module" do
      website_module.update!(status: :inactive, required: false)
      expect { described_class.apply! }.to raise_error(FeatureModules::ModuleNotEnabled)
      expect(website_module.reload).to be_inactive
      expect(Website.where(customer_id: customer.id)).to be_empty
      expect(FeatureModules::CustomerAssignment.where(customer_id: customer.id, feature_module: website_module)).to be_empty
    end

    it "fails without registering or activating a missing global module" do
      website_module.destroy!
      expect { described_class.apply! }.to raise_error(FeatureModules::ModuleNotEnabled)
      expect(FeatureModules::Module.find_by(key: "website")).to be_nil
    end

    it "resumes an owner assignment without changing its configuration or other assignments" do
      assignment = create(:customer_feature_module, :suspended, customer: customer, feature_module: website_module,
                          configuration: { "custom" => "keep" }.to_json)
      other = create(:customer_feature_module, :suspended, feature_module: website_module)
      described_class.apply!
      expect(assignment.reload).to be_active
      expect(assignment.configuration_json).to eq("custom" => "keep")
      expect(other.reload).to be_suspended
    end

    it "rolls back site, pages and module enablement if a later page fails validation" do
      allow(Websites::Activities::SavePage).to receive(:call).and_wrap_original do |method, **args|
        args[:params]["title"] = "" if args[:params]["slug"] == "contact"
        method.call(**args)
      end
      expect { described_class.apply! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(Website.where(customer_id: customer.id)).to be_empty
      expect(WebsitePage.where(customer_id: customer.id)).to be_empty
      expect(FeatureModules::CustomerAssignment.where(customer_id: customer.id, feature_module: website_module)).to be_empty
    end

    it "rolls back partial updates to an existing site on failure" do
      site = described_class.apply!
      before_site = site.attributes
      before_pages = site.pages.map(&:attributes)
      allow(Websites::Activities::SavePage).to receive(:call).and_wrap_original do |method, **args|
        args[:params]["title"] = "" if args[:params]["slug"] == "contact"
        method.call(**args)
      end
      expect { described_class.apply!(locale: :"zh-CN") }.to raise_error(ActiveRecord::RecordInvalid)
      expect(site.reload.attributes).to eq(before_site)
      expect(site.pages.reload.map(&:attributes)).to eq(before_pages)
    end

    context "when seeding the database" do
      before do
        allow(Roles::Operation::SeedReserved).to receive(:call)
        allow(Emails::PlatformTokenSeeds).to receive(:ensure!)
        allow(Oauth::DesktopClient).to receive(:ensure!)
      end

      it "restores a missing owner site once and preserves later owner edits" do
        expect { load Rails.root.join("db/seeds.rb") }.to output.to_stdout
        site = Website.find_by!(customer_id: customer.id)
        site.update!(tagline: "Owner's tagline")
        home = site.home_page
        home.update!(title: "Owner's home")
        site.pages.find_by!(slug: "contact").destroy!
        before_site = site.attributes
        before_pages = site.pages.reload.map(&:attributes)

        expect(described_class).not_to receive(:apply!)
        expect { load Rails.root.join("db/seeds.rb") }.to output.to_stdout
        expect(site.reload.attributes).to eq(before_site)
        expect(site.pages.reload.map(&:attributes)).to eq(before_pages)
      end

      it "does not restore another customer when the platform customer is absent" do
        customer.destroy!
        expect(described_class).not_to receive(:apply!)
        expect { load Rails.root.join("db/seeds.rb") }.to output.to_stdout
        expect(Website.where(customer_id: described_class::CUSTOMER_ID)).to be_empty
      end
    end
  end
end
