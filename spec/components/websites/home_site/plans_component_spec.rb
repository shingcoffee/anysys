# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::HomeSite::PlansComponent, type: :component do
  it "renders all saved reference data in a responsive four-column grid with locale-preserving signup anchors" do
    tiers = %w[Free Starter Pro Enterprise].each_with_index.map do |name, index|
      { name: name, price: ["$0", "$29", "$99", "$499"][index], cadence: "USD / month", body: "Reference plan",
        features: "10 pages\n5 record types\n1 account", button_label: "Start building", button_href: "/auth/sign_up",
        highlight: index == 1 ? "featured" : "standard" }
    end
    I18n.with_locale(:'zh-CN') do
      html = render_inline(described_class.new(theme: website_theme, props: { heading: "Plans", tiers: tiers }))
      expect(html.css("h3").map(&:text)).to eq(%w[Free Starter Pro Enterprise])
      expect(html.css("article li").map { |node| node.text.strip }).to eq(["10 pages", "5 record types", "1 account"] * 4)
      expect(html.css("article a").map { |node| node["href"] }).to eq(["/auth/sign_up?locale=zh-CN"] * 4)
      expect(html.at_css("article").parent.parent["class"]).to include("md:grid-cols-2", "lg:grid-cols-4")
      featured = html.css("article")[1]
      expect(featured["class"]).to include("text-white", "bg-gradient-to-br", "from-[#120a2e]", "h-full")
      expect(featured.parent["class"]).to include("p-0.5", "from-violet-500", "lg:-translate-y-4")
      expect(html.css("article")[0].parent["class"]).not_to include("p-0.5", "lg:-translate-y-4")
      expect(featured.at_css("h3")["class"].split).to include("text-white")
      expect(featured.at_css("li")["class"].split).to include("text-violet-100/90")
      expect(featured.at_css("ul")["class"].split).to include("border-white/15")
      expect(featured.at_css("a")["class"].split).to include("from-violet-600", "text-white", "rounded-full")
      expect(featured.at_css("span")).to have_text(I18n.t("website.public.pricing.featured"))
      expect(html.css("article")[0].at_css("a")["class"].split).to include("bg-slate-900", "text-white")
      expect(html.css("img, button, input")).to be_empty
      expect(html.css("article a").map { |node| node["class"] }).to all(include("min-h-12", "min-w-0", "w-full"))
      expect(html.css("li svg").size).to eq(12)
      expect(html.css("li svg").map { |node| node["aria-hidden"] }).to all(eq("true"))
      expect(html.css("li svg").map { |node| node["focusable"] }).to all(eq("false"))
      expect(html.at_css("section")["class"]).to include("bg-white")
    end
  end

  it "overlaps the pricing hero on the Pricing page" do
    html = render_inline(described_class.new(theme: website_theme, page_role: :pricing, props: { tiers: [{ name: "Free", price: "$0" }] }))
    expect(html.at_css("section")["class"]).to include("-mt-32", "lg:-mt-40", "relative", "z-10")
    expect(html.css("h2")).to be_empty
  end

  it "omits phantom plans and renders an unsafe destination label as ordinary text" do
    html = render_inline(described_class.new(theme: website_theme, props: { heading: "Empty plans", tiers: [] }))
    expect(html.css("article, a")).to be_empty
    html = render_inline(described_class.new(theme: website_theme, props: { tiers: [{ name: "<b>Custom</b>", price: "$17", button_label: "Read", button_href: "//evil.test" }] }))
    expect(html).to have_text("<b>Custom</b>")
    expect(html).to have_text("$17")
    expect(html.css("a, b")).to be_empty
  end

  it "follows saved highlight and recommendation props rather than plan identity, escaping feature text" do
    html = render_inline(described_class.new(theme: website_theme,
      props: { featured_label: "Owner recommendation", tiers: [
        { name: "Starter", price: "$17", highlight: "standard", features: "  Saved quota  \n\nSecond limit" },
        { name: "Custom plan", price: "$42", highlight: "featured", features: "Saved <script>feature</script>" }
      ] }))
    expect(html.css("article").first["class"]).to include("bg-white")
    expect(html.css("article").last["class"]).to include("from-[#120a2e]")
    expect(html.css("li").map { |node| node.text.strip }).to eq(["Saved quota", "Second limit", "Saved <script>feature</script>"])
    expect(html).to have_text("Owner recommendation")
    expect(html.css("script, a, input")).to be_empty
  end
end
