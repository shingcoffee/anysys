# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::HomeSite::StoryComponent, type: :component do
  it "keeps copy first on mobile, respects desktop media side and reuses localized artwork" do
    I18n.with_locale(:'zh-CN') do
      html = render_inline(described_class.new(theme: website_theme, variant: :story,
        props: { heading: "品牌网站", body: "可编辑", image_side: "left", image_url: "/site-images/anysys/anysys-brand-studio.svg" }))
      expect(html).to have_css('img[alt="品牌网站"][loading="lazy"]')
      expect(html.css("svg text").map(&:text)).to eq([I18n.t("website.platform.catalog.theme.swatches")])
      expect(html.at_css("h2").parent["class"]).to include("lg:order-2")
      expect(html.at_css("h2")["class"]).to include("tracking-normal")
      expect(html.css("[class]").any? { |node| node["class"].include?("aspect-[4/3]") }).to be(true)
    end
  end

  it "frames a bundled photo with page-specific decorative chips" do
    I18n.with_locale(:'zh-CN') do
      html = render_inline(described_class.new(theme: website_theme, variant: :story, page_role: :home,
        props: { heading: "Saved", body: "Copy", image_url: "/site-images/anysys/anysys-photo-studio-owner.webp" }))
      expect(html).to have_css('img[src="/site-images/anysys/anysys-photo-studio-owner.webp"][alt="Saved"]')
      chips = html.css('[aria-hidden="true"].animate-float')
      expect(chips.map { |node| node.text.strip }).to eq(I18n.t("website.home_site.story_chips.home"))
    end
    html = render_inline(described_class.new(theme: website_theme, variant: :story,
      props: { heading: "Saved", image_url: "/site-images/anysys/anysys-photo-studio-owner.webp" }))
    expect(html.css(".animate-float")).to be_empty
  end

  it "omits invalid art entirely and escapes blank-line separated editorial paragraphs" do
    html = render_inline(described_class.new(theme: website_theme, variant: :editorial,
      props: { heading: "Mission", body: "First <script>alert(1)</script>.\n\nSecond\nline.", image_url: "javascript:alert(1)" }))
    expect(html.css("p").map(&:text)).to eq(["First <script>alert(1)</script>.", "Second\nline."])
    expect(html.css("img, svg, script")).to be_empty
    expect(html.at_css("h2").parent["class"]).to include("lg:col-span-5")
    expect(html.at_css("p")["class"]).to include("text-[17px]", "leading-8")
    expect(html.at_css("section")["class"]).to include("py-16", "lg:py-24")
  end

  it "uses a gradient-bordered Contact note without an alert or manufactured action" do
    html = render_inline(described_class.new(theme: website_theme, variant: :contact_note, props: { heading: "Channel", body: "Not available" }))
    expect(html.at_css("section")["class"]).to include("pt-16", "lg:pt-24")
    expect(html.at_css("h2")["class"]).to include("text-[28px]")
    frame = html.at_css("h2").ancestors.find { |node| node["class"].to_s.include?("p-px") }
    expect(frame["class"]).to include("rounded-[2rem]", "bg-gradient-to-br")
    expect(html.css('[role="alert"], a, button')).to be_empty
  end

  it "does not render an unavailable bundled-art path or create a placeholder" do
    html = render_inline(described_class.new(theme: website_theme,
      props: { heading: "Saved story", body: "Still readable", image_url: "/site-images/anysys/anysys-missing.svg" }))
    expect(html).to have_text("Still readable")
    expect(html.css("img, svg")).to be_empty
  end

  it "gives About mission prose a larger lead paragraph without interpreting content" do
    heading_classes = ["Owner mission title", "任意工艺标题"].map do |heading|
      html = render_inline(described_class.new(theme: website_theme, page_role: :about, variant: :editorial,
        props: { heading: heading, body: "Saved first paragraph.\n\nSaved second paragraph." }))
      expect(html.css("h2").map(&:text)).to eq([heading])
      expect(html.css("p").map(&:text)).to eq(["Saved first paragraph.", "Saved second paragraph."])
      expect(html.css("p").first["class"]).to include("lg:text-[24px]", "text-slate-800")
      expect(html.css("p").last["class"]).to include("text-[17px]")
      expect(html.at_css("p").parent["class"]).to include("w-full", "lg:col-span-7")
      expect(html.css("img, svg, blockquote, a")).to be_empty
      html.at_css("h2")["class"]
    end
    expect(heading_classes.uniq.size).to eq(1)
  end

  it "omits an empty availability panel instead of displaying an empty bordered card" do
    html = render_inline(described_class.new(theme: website_theme, variant: :contact_note,
      props: { heading: " ", body: "\n", image_url: "javascript:alert(1)" }))
    expect(html.css("section, h2, p, img")).to be_empty
  end
end
