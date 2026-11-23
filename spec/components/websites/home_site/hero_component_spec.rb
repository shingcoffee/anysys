# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::HomeSite::HeroComponent, type: :component do
  def accent_lines(html) = html.css("h1 span.bg-clip-text").map(&:text)

  it "escapes block lines and accents only the final line of a multiline headline" do
    html = render_inline(described_class.new(theme: website_theme, page_role: :home, variant: :lead,
      props: { headline: "Your <script>business</script>.\nBuilt your way.", media_mode: "none" }))
    expect(html.css("h1 > span").map(&:text)).to eq(["Your <script>business</script>.", "Built your way."])
    expect(accent_lines(html)).to eq(["Built your way."])
    expect(html.css("script")).to be_empty

    html = render_inline(described_class.new(theme: website_theme, page_role: :home, props: { headline: "Owner headline" }))
    expect(accent_lines(html)).to be_empty
  end

  it "renders a full-bleed dark aurora surface with Chinese normal tracking" do
    I18n.with_locale(:'zh-CN') do
      html = render_inline(described_class.new(theme: website_theme, variant: :lead, page_role: :platform,
        props: { headline: "业务系统与品牌网站，\n在同一处构建。" }))
      expect(html.at_css("section")["class"]).to include("bg-slate-950", "isolate", "overflow-hidden")
      expect(html.at_css("h1")["class"]).to include("tracking-normal", "lg:text-[84px]", "text-white")
      expect(accent_lines(html)).to eq(["在同一处构建。"])
      expect(html.css("section > div[aria-hidden='true'] span.animate-aurora")).not_to be_empty
    end
  end

  it "shows the New badge, trust row and localized product mockup only on the Home lead" do
    I18n.with_locale(:'zh-CN') do
      home = render_inline(described_class.new(theme: website_theme, variant: :lead, page_role: :home,
        props: { eyebrow: "Saved eyebrow", headline: "Saved" }))
      expect(home.at_css("p").element_children.first.text).to eq(I18n.t("website.home_site.hero_badge"))
      expect(home.css("ul li").map { |node| node.text.strip }).to eq(I18n.t("website.home_site.trust"))
      expect(home).to have_css(%([role="img"][aria-label="#{I18n.t('website.home_site.mockup.label')}"]))
      expect(home).to have_text(I18n.t("website.home_site.mockup.assistant.message"))
    end

    platform = render_inline(described_class.new(theme: website_theme, variant: :lead, page_role: :platform,
      props: { eyebrow: "Saved eyebrow", headline: "Saved" }))
    expect(platform.at_css("p").text.squish).to eq("Saved eyebrow")
    expect(platform).to have_css('[role="img"]')

    pricing = render_inline(described_class.new(theme: website_theme, variant: :pricing, page_role: :pricing, props: { headline: "Saved" }))
    expect(pricing.css('[role="img"], ul')).to be_empty
  end

  it "omits none-mode art and blank actions, preserving a localized real CTA and invalid label as text" do
    I18n.with_locale(:'zh-CN') do
      html = render_inline(described_class.new(theme: website_theme, customer_id: 81_721_200, variant: :pricing,
        props: { headline: "Plans", media_mode: "none", image_url: "/site-images/anysys/anysys-brand-studio.svg",
                 primary_label: "Start", primary_href: "/auth/sign_up", secondary_label: "Literal", secondary_href: "javascript:alert(1)" }))
      expect(html.at_css("a")["href"]).to eq("/auth/sign_up?locale=zh-CN")
      expect(html.css("a").size).to eq(1)
      expect(html).to have_text("Literal")
      expect(html.css("img")).to be_empty
      expect(html.at_css("section")["class"]).to include("pb-40", "lg:pb-52")
    end
    html = render_inline(described_class.new(theme: website_theme, variant: :editorial, props: {}))
    expect(html.css("a, h1, img")).to be_empty
  end

  it "preserves an explicitly enabled valid custom hero image" do
    html = render_inline(described_class.new(theme: website_theme, props: { headline: "Custom", media_mode: "image", image_url: "https://cdn.example/custom.jpg" }))
    expect(html).to have_css('img[src="https://cdn.example/custom.jpg"][alt="Custom"][loading="eager"]')
  end

  it "centres the pricing lead with readable reference copy and safe extreme-width reflow" do
    html = render_inline(described_class.new(theme: website_theme, variant: :pricing,
      props: { headline: "Simple pricing.", subhead: "Reference monthly prices in USD." }))
    heading = html.at_css("h1")
    expect(heading["class"].split).to include("min-w-0", "w-full", "text-[36px]", "lg:text-[66px]")
    expect(heading.parent["class"]).to include("w-full", "gap-6", "mx-auto", "items-center", "text-center")
    subhead = html.css("p").find { |node| node.text == "Reference monthly prices in USD." }
    expect(subhead["class"]).to include("text-[18px]", "mx-auto", "max-w-3xl", "text-slate-300")
    expect(heading.ancestors.any? { |node| node["class"].to_s.include?("[overflow-wrap:anywhere]") }).to be(true)
    expect(heading.ancestors.any? { |node| node["class"].to_s.include?("max-w-[1280px]") }).to be(true)
    expect(html.css("a, button")).to be_empty
  end

  it "uses an 18px lead and pill gradient primary action with an arrow" do
    html = render_inline(described_class.new(theme: website_theme, variant: :lead,
      props: { headline: "Saved headline", subhead: "Saved lead", primary_label: "Start building", primary_href: "/auth/sign_up" }))
    expect(html.css("p").find { |node| node.text == "Saved lead" }["class"]).to include("text-[18px]")
    primary = html.at_css("a")
    expect(primary["class"]).to include("min-h-12", "min-w-0", "text-[16px]", "rounded-full", "from-violet-600")
    expect(primary.text.strip).to eq("Start building")
    expect(primary.at_css("svg")["aria-hidden"]).to eq("true")
  end

  it "places the saved About image alongside copy with decorative localized chips" do
    I18n.with_locale(:'zh-CN') do
      html = render_inline(described_class.new(theme: website_theme, variant: :about, page_role: :about,
        props: { headline: "Owner headline\n第二行", subhead: "Saved description", media_mode: "image",
                 image_url: "/site-images/anysys/anysys-photo-about-team.webp" }))
      expect(html.css("h1").size).to eq(1)
      expect(html).to have_css('img[src="/site-images/anysys/anysys-photo-about-team.webp"][loading="eager"][alt="Owner headline 第二行"]')
      expect(html.at_css("h1").parent["class"]).to include("lg:col-span-6", "text-left")
      split = html.at_css("h1").parent.parent
      expect(split["class"]).to include("grid-cols-1", "lg:grid-cols-12", "items-center")
      expect(split.element_children.last["class"]).to include("lg:col-span-6")
      chips = html.css('[aria-hidden="true"].animate-float')
      expect(chips.map { |node| node.text.strip }).to eq(I18n.t("website.home_site.hero_chips.about"))
      expect(html.css("a, button")).to be_empty
    end
  end

  it "keeps localized illustration overlays for bundled SVG art" do
    html = render_inline(described_class.new(theme: website_theme, variant: :about, page_role: :about,
      props: { headline: "Owner", media_mode: "image", image_url: "/site-images/anysys/anysys-about-idea-hero.svg" }))
    expect(html.css("svg text").map(&:text)).to eq([I18n.t("website.home_site.illustration.idea")])
  end

  it "falls back to text-first About for disabled or invalid saved media without substituting artwork" do
    [
      ["none", "/site-images/anysys/anysys-about-idea-hero.svg"],
      ["image", "javascript:alert(1)"],
      ["image", "/site-images/anysys/anysys-missing.svg"],
      ["image", "/site-images/anysys/anysys-photo-missing.jpg"],
      ["image", "/site-images/anysys/anysys-photo-missing.webp"]
    ].each do |mode, url|
      html = render_inline(described_class.new(theme: website_theme, variant: :about, page_role: :about,
        props: { headline: "Owner-edited heading", media_mode: mode, image_url: url }))
      expect(html).to have_text("Owner-edited heading")
      expect(html.css("img, svg")).to be_empty
      expect(html.at_css("h1").parent["class"]).not_to include("lg:col-span-6")
    end
  end

  it "splits Contact around its saved photo and stays text-first without one" do
    html = render_inline(described_class.new(theme: website_theme, variant: :contact, page_role: :contact,
      props: { headline: "Saved welcome\nSaved second line", subhead: "Saved introduction", media_mode: "image",
               image_url: "/site-images/anysys/anysys-photo-contact.webp" }))
    expect(html.css("h1 > span").map(&:text)).to eq(["Saved welcome", "Saved second line"])
    expect(html.at_css("h1")["class"]).to include("lg:text-[56px]")
    expect(html.css('[aria-hidden="true"].animate-float').map { |node| node.text.strip }).to eq(I18n.t("website.home_site.hero_chips.contact"))
    expect(html.css("form, input, button, a")).to be_empty

    html = render_inline(described_class.new(theme: website_theme, variant: :contact, page_role: :contact,
      props: { headline: "Saved welcome", media_mode: "none" }))
    expect(html.css("img, svg, form, input, button, a")).to be_empty
    expect(html.at_css("h1").parent["class"]).to include("text-center")
  end
end
