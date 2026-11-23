# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeveloperDocs::Renderer do
  def render(markdown, **options)
    described_class.call(
      markdown,
      link_resolver: ->(slug) { "/docs/#{slug}" },
      labels: { "attention" => "Pay attention", "note" => "Note" },
      anchor_label: "Link to this section",
      **options
    )
  end

  it "builds heading ids and a same-page anchor" do
    result = render(<<~MD)
      ## Summary

      Intro

      ## Where to pay attention

      Careful
    MD

    ids = result.headings.map { |heading| heading[:id] }
    expect(ids).to eq(%w[summary where-to-pay-attention])
    ids.each { |id| expect(result.html).to include(%(id="#{id}")) }
    expect(result.html).to include('href="#summary"')
    expect(result.html).to include('aria-label="Link to this section"')
  end

  it "renders an attention callout and leaves fenced markers as code" do
    result = render(<<~MD)
      ## Summary

      :::attention
      Do not read `current_version` here.
      :::

      ```
      :::attention
      not a callout
      :::
      ```
    MD

    expect(result.html).to include("Pay attention")
    expect(result.html).to include("Do not read")
    expect(result.html).to include("not a callout")
    expect(result.html).to include("<aside")
    expect(result.html.scan("<aside").size).to eq(1)
  end

  it "highlights fenced ruby and rewrites catalog links" do
    result = render(<<~MD)
      ## Key code

      See the [entity builder](entity-builder#summary).

      ```ruby
      def platform_owner?
        owner?
      end
      ```

      <script>alert(1)</script>
      [bad](javascript:alert(1))
    MD

    expect(result.html).to include('href="/docs/entity-builder#summary"')
    expect(result.html).to include("platform_owner?")
    expect(result.html).to include("<pre")
    expect(result.html).not_to include("<script")
    expect(result.html).not_to include("javascript:")
  end

  it "ids Chinese headings without dropping the visible text" do
    result = render(<<~MD)
      ## 概要

      正文
    MD

    expect(result.headings.first[:text]).to eq("概要")
    expect(result.html).to include("概要")
    expect(result.html).to include(%(id="#{result.headings.first[:id]}"))
  end

  context "with explicitly enabled screenshots" do
    let(:options) do
      {
        screenshot_root: "/help/docs/screenshots",
        screenshot_labels: { full_size: "View full size", open: "View full size: %{caption}" }
      }
    end
    let(:source) { "/help/docs/screenshots/en/forms-publishing.png" }

    def screenshot(markdown, **overrides)
      Nokogiri::HTML5.fragment(render(markdown, **options, **overrides).html)
    end

    def sanitize_html(html)
      renderer = described_class.new(
        "", link_resolver: ->(slug) { "/docs/#{slug}" }, labels: {}, anchor_label: "Section", **options
      )
      Nokogiri::HTML5.fragment(renderer.send(:sanitize, Nokogiri::HTML5.fragment(html)))
    end

    ["en/forms-publishing.png", "zh-CN/forms-publishing.png", "en/1.png", "zh-CN/screen-2-state.png"].each do |path|
      it "renders #{path} as a captioned figure with identical native links" do
        url = "/help/docs/screenshots/#{path}"
        fragment = screenshot(%(![Visible controls](#{url} "Check launch status.")))
        figure = fragment.at_css("figure")

        expect(fragment.css("figure").size).to eq(1)
        expect(figure.at_css("img").attributes.transform_values(&:value)).to eq(
          "src" => url, "alt" => "Visible controls", "loading" => "lazy", "decoding" => "async"
        )
        expect(figure.css("a").map { |anchor| anchor["href"] }).to eq([url, url])
        expect(figure.at_css("a[aria-label]")["aria-label"]).to eq("View full size: Check launch status.")
        expect(figure.at_css("figcaption > span").text).to eq("Check launch status.")
        expect(figure.at_css("figcaption > a").text).to eq("View full size")
        expect(figure.css("a[target], img[title]")).to be_empty
      end
    end

    it "uses explicitly supplied localized labels, including the image-link caption" do
      fragment = screenshot(%(![发布控件](/help/docs/screenshots/zh-CN/forms-publishing.png "核对发布状态。")),
                            screenshot_labels: { full_size: "查看原图", open: "查看原图：%{caption}" })

      expect(fragment.at_css("figure > a")["aria-label"]).to eq("查看原图：核对发布状态。")
      expect(fragment.at_css("figcaption > a").text).to eq("查看原图")
    end

    it "escapes caption, alt, and labels as text instead of inserting HTML or attributes" do
      alt = '<script>Alt</script> & "controls"'
      caption = '<img src=x onerror=alert(1)> & "caption"'
      fragment = screenshot("![#{alt}](#{source} '#{caption}')",
                            screenshot_labels: { full_size: '<b>Full size</b>', open: 'Open "image": %{caption}' })

      # HTML may retain angle brackets inside quoted attributes. Verify their
      # meaning and safety after serialization and HTML5 parsing instead.
      round_trip = Nokogiri::HTML5.fragment(fragment.to_html)
      [fragment, round_trip].each do |document|
        expect(document.at_css("img").attributes.transform_values(&:value)).to eq(
          "src" => source, "alt" => alt, "loading" => "lazy", "decoding" => "async"
        )
        expect(document.at_css("figure > a").attributes.transform_values(&:value)).to eq(
          "href" => source, "aria-label" => "Open \"image\": #{caption}"
        )
        caption_node = document.at_css("figcaption > span")
        expect(caption_node.text).to eq(caption)
        expect(caption_node.children).to all(be_text)
        expect(caption_node.inner_html).to include("&lt;img src=x onerror=alert(1)&gt;", "&amp;")
        full_size = document.at_css("figcaption > a")
        expect(full_size.text).to eq("<b>Full size</b>")
        expect(full_size.children).to all(be_text)
        expect(full_size.attributes.transform_values(&:value)).to eq("href" => source)
        expect(document.css("*").map(&:name)).to eq(%w[figure a img figcaption span a])
        expect(document.css("figure, figcaption, span").map(&:attributes)).to all(be_empty)
        expect(document.css("script, b, [onerror]")).to be_empty
        event_attributes = document.css("*").flat_map(&:attribute_nodes).select { |attribute| attribute.name.match?(/\Aon/i) }
        expect(event_attributes).to be_empty
      end
    end

    [
      "https://example.com/image.png", "http://example.com/image.png", "//example.com/image.png",
      "data:image/png;base64,AAAA", "blob:https://example.com/123", "javascript:alert(1)",
      "/help/docs/screenshots/en/forms.svg", "/help/docs/screenshots/en/forms.PNG",
      "help/docs/screenshots/en/forms.png", "./help/docs/screenshots/en/forms.png",
      "/help/docs/screenshots/en/nested/forms.png", "/help/docs/screenshots/en/../forms.png",
      "/help/docs/screenshots/en/%2e%2e/forms.png", "/help/docs/screenshots/en/%66orms.png",
      "/help/docs/screenshots/&#101;n/forms.png", "/help/docs/screenshots/en/forms\\-publishing.png",
      "/help/docs/screenshots/en/forms.png?download=1", "/help/docs/screenshots/en/forms.png#full",
      " /help/docs/screenshots/en/forms.png", "/help/docs/screenshots/en/forms.png ",
      "/help/docs/screenshots/en/forms.png\t", "/help/docs/screenshots/fr/forms.png",
      "/help/docs/screenshots/EN/forms.png", "/help/docs/screenshots/en/Forms.png",
      "/help/docs/screenshots/en/forms_list.png", "/help/docs/screenshots/en/-forms.png",
      "/help/docs/screenshots/en/forms--list.png", "/help/docs/screenshots/en/forms-.png",
      "/other/screenshots/en/forms.png", "/help/docs/screenshots//en/forms.png"
    ].each do |url|
      it "falls back to plain alt for the rejected source #{url.inspect}" do
        fragment = screenshot(%(![Useful alt](<#{url}> "Caption")))

        expect(fragment.css("img, figure, a[href]")).to be_empty
        expect(fragment.text.strip).to eq("Useful alt")
      end
    end

    it "does not turn raw HTML images or linked Markdown images into figures" do
      fragment = screenshot(<<~MD)
        <a href="https://example.com"><img src="#{source}" alt="Raw &lt;controls&gt;" title="Raw caption" onerror="bad()"></a>

        [![Linked controls](#{source} "Caption")](https://example.com)
      MD

      expect(fragment.css("img, figure, a[href]")).to be_empty
      expect(fragment.text).to include("Raw <controls>", "Linked controls")
      expect(fragment.css("controls")).to be_empty
    end

    it "escapes rejected-image alt text and removes a surrounding image link" do
      fragment = screenshot(<<~MD)
        [![<script>Useful alt</script>](https://example.com/image.png "Caption")](https://example.com/full-size.png)
      MD

      expect(fragment.css("img, figure, a, script")).to be_empty
      expect(fragment.text.strip).to eq("<script>Useful alt</script>")
    end

    it "requires nonblank alt, a caption title, and a standalone image paragraph" do
      fragment = screenshot(<<~MD)
        ![](#{source} "Caption")

        ![No caption](#{source})

        ![Blank caption](#{source} "   ")

        Inline ![Inline controls](#{source} "Caption") in a sentence.
      MD

      expect(fragment.css("img, figure, a[href]")).to be_empty
      expect(fragment.text).to include("No caption", "Blank caption", "Inline controls")
    end

    it "ignores author attributes and emits only server-owned image attributes" do
      fragment = screenshot(<<~MD)
        ![Controls](#{source} "Caption"){: .author-style onerror="bad()" style="display:none" srcset="https://example.com/image.png 2x" loading="eager" decoding="sync"}
      MD

      expect(fragment.at_css("img").attributes.transform_values(&:value)).to eq(
        "src" => source, "alt" => "Controls", "loading" => "lazy", "decoding" => "async"
      )
      expect(fragment.css("[onerror], [style], [srcset], .author-style")).to be_empty
    end

    it "inserts images after catalog rewriting without allowing arbitrary static Markdown links" do
      fragment = screenshot(<<~MD)
        [Guide](entity-builder.md#summary) and [External](https://example.com/help).

        [Author image link](#{source}) and [Unknown](not-a-guide).

        ![Controls](#{source} "Caption")
      MD

      expect(fragment.css("a[href]").map { |anchor| anchor["href"] }).to eq(
        ["/docs/entity-builder#summary", "https://example.com/help", source, source]
      )
      expect(fragment.css("figure a[href]").size).to eq(2)
    end

    it "renders standalone images in callouts while leaving fenced image syntax as code" do
      fragment = screenshot(<<~MD)
        :::note
        ![Controls](#{source} "Caption")
        :::

        ```markdown
        ![Code sample](#{source} "Not a figure")
        ```
      MD

      expect(fragment.css("aside figure").size).to eq(1)
      expect(fragment.css("figure").size).to eq(1)
      expect(fragment.at_css("pre").text).to include("![Code sample]")
    end

    it "scrubs image-only and figure attributes from inappropriate tags and validates controlled values" do
      fragment = sanitize_html(<<~HTML)
        <figure class="author" src="#{source}">
          <a href="#{source}" aria-label="Open" src="#{source}" loading="lazy" onclick="bad()">
            <img src="#{source}" alt="Controls" loading="eager" decoding="sync" srcset="bad" style="bad" onerror="bad()" id="bad" class="bad" href="#{source}">
          </a>
          <figcaption alt="Caption" decoding="async">Caption</figcaption>
        </figure>
        <p src="#{source}" alt="Paragraph" loading="lazy" decoding="async">Paragraph</p>
      HTML

      expect(fragment.at_css("img").attributes.transform_values(&:value)).to eq("src" => source, "alt" => "Controls")
      expect(fragment.at_css("a").attributes.transform_values(&:value)).to eq("href" => source, "aria-label" => "Open")
      expect(fragment.at_css("figure").attributes).to be_empty
      expect(fragment.at_css("figcaption").attributes).to be_empty
      expect(fragment.at_css("p").attributes).to be_empty
    end

    it "rechecks image sources and full-size links during final sanitization" do
      fragment = sanitize_html(<<~HTML)
        <figure>
          <a href="/help/docs/screenshots/en/../forms.png"><img src="/help/docs/screenshots/en/../forms.png" alt="Unsafe &lt;controls&gt;" onerror="bad()"></a>
          <figcaption><a href="https://example.com/image.png">External full size</a></figcaption>
        </figure>
        <figure><a href="#{source}?download=1">Query</a><a href="#{source}#full">Fragment</a><a href="/docs/entity-builder">Guide</a></figure>
        <a href="#{source}">Unowned screenshot link</a>
      HTML

      expect(fragment.css("img, a[href]")).to be_empty
      expect(fragment.text).to include("Unsafe <controls>")
      expect(fragment.css("controls, [onerror]")).to be_empty
    end

    it "retains reference image stripping when the screenshot root is nil" do
      fragment = screenshot(%(![Controls](#{source} "Caption")), screenshot_root: nil)

      expect(fragment.css("img, figure, a[href]")).to be_empty
      expect(fragment.text).not_to include("Controls", "Caption", "View full size")
    end

    it "requires explicit labels when enabled and rejects roots outside the exact policy" do
      expect { render("", screenshot_root: "/help/docs/screenshots") }.to raise_error(ArgumentError, /screenshot_labels/)
      expect { render("", **options, screenshot_root: "/other/screenshots") }.to raise_error(ArgumentError, /screenshot root/)
    end
  end
end
