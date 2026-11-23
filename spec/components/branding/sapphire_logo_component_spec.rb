# frozen_string_literal: true

require "rails_helper"

RSpec.describe Branding::SapphireLogoComponent, type: :component do
  # The rack_test driver parses output as HTML and lowercases SVG attribute
  # names, so we assert against the raw rendered markup which preserves case.
  def html_for(**opts)
    render_inline(described_class.new(**opts)).to_html
  end

  it "stands the gem upright with its symmetry axis vertical (rotate 45) and crops tight" do
    html = html_for

    expect(html).to include('viewBox="-99.28 24.33 695.48 575.82"')
    expect(html).to include('transform="rotate(45 238.449 251.856)"')
  end

  it "renders only the shape — no wordmark text" do
    expect(html_for).not_to include("SAPPHIRE")
  end

  it "uses the site's violet palette rather than the old blue facets" do
    html = html_for

    expect(html).to include("#7f22fe") # public site's violet primary
    expect(html).to include("#6d28d9") # core facet
    expect(html).to include("#ede9fe") # light reflection
    expect(html).not_to match(/#(?:072a7a|08276e|0a2f86|0f44b5|1a4fc2|1e5ad2|2a66de|316fe6|b0cdf7)/)
  end

  it "preserves the source geometry byte-for-byte (a signature path)" do
    expect(html_for).to include(
      "M106.8 106.12c74.27-73.64 170.01-117.15 206.76-80.08"
    )
  end

  it "applies the requested Tailwind height" do
    expect(html_for(size: :sm)).to include("h-8")
  end

  it "accepts a raw Tailwind height class for size" do
    expect(html_for(size: "h-20")).to include("h-20")
  end

  it "namespaces gradient ids per instance so multiple logos never collide" do
    id1 = html_for[/grad1-([0-9a-f]+)/, 1]
    id2 = html_for[/grad1-([0-9a-f]+)/, 1]

    expect(id1).to be_present
    expect(id1).not_to eq(id2)
  end

  it "can sit beside visible brand text without a second accessible name" do
    html = html_for(decorative: true, css_class: "shrink-0")

    expect(html).to include('aria-hidden="true"')
    expect(html).to include('focusable="false"')
    expect(html).to include("shrink-0")
    expect(html).not_to include("aria-label")
    expect(html).not_to include('role="img"')
  end

  it "wires the namespaced id through to the gradient reference" do
    html = html_for
    uid  = html[/grad1-([0-9a-f]+)/, 1]

    expect(html).to include(%(url(#grad1-#{uid})))
  end
end
