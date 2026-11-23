# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::IllustrationComponent, type: :component do
  let(:src) { "/site-images/anysys/anysys-website-draft.svg" }

  around do |example|
    I18n.with_locale(:en) { example.run }
  end

  # Expected wording and source transform chains from the UX handoff. Checking
  # rendered ancestry catches reversed or flattened nested transforms.
  {
    "anysys-home-workspace-hero.svg" => [
      ["Records", "记录", ["translate(-172 -30.9) scale(1.06)"]],
      ["Website", "网站", ["translate(-172 -30.9) scale(1.06)", "rotate(7 1650 440)"]]
    ],
    "anysys-ai-draft.svg" => [
      ["Draft", "草稿", ["translate(144 90) scale(.82)", "rotate(3 861 667)"]]
    ],
    "anysys-website-draft.svg" => [["Draft", "草稿", ["rotate(-2 806 500)"]]],
    "anysys-brand-studio.svg" => [["Theme", "主题", []]],
    "anysys-review-publish.svg" => [["Preview", "预览", ["rotate(4 984 535)"]]],
    "anysys-records-forms.svg" => [
      ["Records", "记录", ["rotate(-3 704 478)"]],
      ["Forms", "表单", ["rotate(4 1113 555)"]]
    ],
    "anysys-members-payments.svg" => [
      ["Members", "会员", ["rotate(-3 716 566)"]],
      ["Payments", "支付", ["rotate(7 1120 661)"]]
    ],
    "anysys-email-sms.svg" => [
      ["Email", "邮件", ["rotate(-7 653 500)"]],
      ["SMS", "短信", ["rotate(7 1118 471)"]]
    ],
    "anysys-local-desktop.svg" => [["Local data", "本地数据", ["matrix(.99 .06 -.08 .99 68 -46)"]]],
    "anysys-record-control.svg" => [["Records", "记录", []]],
    "anysys-local-privacy.svg" => [["Local data", "本地数据", ["translate(-120 -75) scale(1.15)"]]],
    "anysys-platform-workspace-hero.svg" => [["Records", "记录", ["rotate(2 826 587)"]]],
    "anysys-pricing-growth-hero.svg" => [["Plan", "套餐", ["rotate(-3 621 526)"]]],
    "anysys-about-idea-hero.svg" => [["Idea", "想法", ["rotate(-6 448 584)"]]],
    "anysys-contact-conversation-hero.svg" => [
      ["Idea", "想法", ["rotate(-7 533 499)"]],
      ["Goals", "目标", ["rotate(6 1091 616)"]]
    ]
  }.each do |filename, labels|
    it "renders the bilingual wording and source transform order for #{filename}" do
      path = "/site-images/anysys/#{filename}"
      expect(described_class.known?(path)).to be(true)

      [:en, :"zh-CN"].each_with_index do |locale, column|
        I18n.with_locale(locale) do
          fragment = render_inline(described_class.new(src: path, alt: "Owner's heading"))
          expect(fragment.css("svg text").map(&:text)).to eq(labels.map { |label| label[column] })
          expect(fragment.at_css("img")["alt"]).to eq("Owner's heading")
          expect(fragment.at_css("img")["src"]).to eq(path)
          expect(fragment.css("svg rect").size).to eq(labels.size)

          fragment.css("svg text").each_with_index do |node, index|
            transforms = node.ancestors("g").reverse.filter_map { |group| group["transform"] }
            expect(transforms).to eq(labels[index][2])
          end

          view_box = filename == "anysys-home-workspace-hero.svg" ? "0 0 2400 1030" : "0 0 1600 1000"
          expect(rendered_content).to include(%(viewBox="#{view_box}"), 'preserveAspectRatio="xMidYMid slice"')
        end
      end
    end
  end

  it "resolves locale at render time even when constructed in a different locale" do
    english_component = described_class.new(src: src)

    I18n.with_locale(:"zh-CN") do
      fragment = render_inline(english_component)
      expect(fragment.at_css("svg text").text).to eq("草稿")
    end

    chinese_component = I18n.with_locale(:"zh-CN") { described_class.new(src: src) }
    fragment = render_inline(chinese_component)
    expect(fragment.at_css("svg text").text).to eq("Draft")
  end

  it "escapes translated SVG text and owner-supplied alt text" do
    wording = '</text></g></svg><script>alert("label")</script> & copy'
    alt = 'Owner" onerror="alert(1)"><img src=x onerror="alert(2)"> & "copy"'
    component = described_class.new(src: src, alt: alt)
    allow(component).to receive(:t).with("website.home_site.preview.draft").and_return(wording)

    fragment = render_inline(component)

    expect(fragment.at_css("svg text").text).to eq(wording)
    expect(fragment.at_css("img")["alt"]).to eq(alt)
    expect(fragment.css("script, [onerror]")).to be_empty
    expect(fragment.css("img").size).to eq(1)
    expect(rendered_content).to include("&lt;/text&gt;", "&lt;/svg&gt;", "&lt;script&gt;", "&lt;img")
  end

  it "retains one native accessibility node with lazy loading and async decoding" do
    fragment = render_inline(described_class.new(src: src, alt: "Owner's custom title"))

    expect(fragment.css("img").size).to eq(1)
    image = fragment.at_css("img")
    expect(image["alt"]).to eq("Owner's custom title")
    expect(image["loading"]).to eq("lazy")
    expect(image["decoding"]).to eq("async")
    expect(image["aria-hidden"]).to be_nil

    overlay = fragment.at_css("svg")
    expect(overlay["aria-hidden"]).to eq("true")
    expect(overlay["focusable"]).to eq("false")
    expect(overlay["role"]).to be_nil
    expect(overlay.css("title, desc, a, image, foreignObject, script, [tabindex], [role]")).to be_empty
  end

  it "preserves decorative empty alt and the caller's eager loading choice" do
    fragment = render_inline(described_class.new(src: src, alt: "", eager: true))

    expect(fragment.at_css("img")["alt"]).to eq("")
    expect(fragment.at_css("img")["loading"]).to eq("eager")
    expect(fragment.at_css("img")["decoding"]).to eq("async")
  end

  it "puts positioning, sizing, stacking, rounding and hover transforms on the composed frame" do
    css_class = "absolute inset-0 -z-10 size-full rounded-2xl md:rounded-3xl object-cover transition duration-700 ease-out group-hover:scale-[1.03]"
    fragment = render_inline(described_class.new(src: src, css_class: css_class))
    frame = fragment.at_css("div")

    expect(frame["class"].split).to contain_exactly(*(css_class.split - ["object-cover"] + ["overflow-hidden"]))
    expect(frame["class"].split).not_to include("relative")
    expect(frame.at_css("img")["class"].split).to contain_exactly("absolute", "inset-0", "size-full", "object-cover", "object-center")
    expect(frame.at_css("svg")["class"].split).to contain_exactly("absolute", "inset-0", "size-full", "pointer-events-none")
  end

  it "adds a relative containing frame when the caller only supplies responsive sizes" do
    fragment = render_inline(described_class.new(src: src, css_class: "h-48 w-full md:h-64"))

    expect(fragment.at_css("div")["class"].split).to contain_exactly("relative", "h-48", "w-full", "md:h-64", "overflow-hidden")
  end

  def expect_nameplate(fragment, label:, plate:, text:, fill:, text_fill:, radius: 10, anchor: "start")
    node = fragment.css("svg text").find { |item| item.text == label }
    expect(node).to be_present
    rectangle = node.parent.at_css("rect")
    expect(%w[x y width height].map { |attribute| rectangle[attribute] }).to eq(plate.map(&:to_s))
    expect(rectangle["rx"]).to eq(radius.to_s)
    expect(rectangle["fill"]).to eq(fill)
    expect(%w[x y font-size].map { |attribute| node[attribute] }).to eq(text.map(&:to_s))
    expect(node["text-anchor"]).to eq(anchor)
    expect(node["fill"]).to eq(text_fill)
    expect(node["font-weight"]).to eq("600")
    expect(node["class"].split).to contain_exactly("font-sans", "font-semibold")
    expect(node["textLength"]).to be_nil
    expect(node["textlength"]).to be_nil
  end

  it "matches Home's large-viewBox white table and rotated rear browser headers" do
    fragment = render_inline(described_class.new(src: "/site-images/anysys/anysys-home-workspace-hero.svg"))

    expect_nameplate(fragment, label: "Records", plate: [991, 373, 348, 60], text: [1000, 423, 64], fill: "#FAF9FF", text_fill: "#3C286B")
    expect_nameplate(fragment, label: "Website", plate: [1467, 166, 332, 58], text: [1480, 216, 56], fill: "#FAF9FF", text_fill: "#3C286B", radius: 6)
    expect(fragment.at_css("img")["transform"]).to be_nil
  end

  it "places Theme in the preview navigation strip that survives the wide bento crop" do
    fragment = render_inline(described_class.new(src: "/site-images/anysys/anysys-brand-studio.svg"))

    expect_nameplate(fragment, label: "Theme", plate: [655, 294, 295, 76], text: [670, 354, 64], fill: "#FAF9FF", text_fill: "#3C286B")
  end

  it "enlarges Platform Records into the table's upper margin while retaining its baseline" do
    fragment = render_inline(described_class.new(src: "/site-images/anysys/anysys-platform-workspace-hero.svg"))

    expect_nameplate(fragment, label: "Records", plate: [611, 398, 342, 76], text: [620, 461, 72], fill: "#493481", text_fill: "#FFFFFF")
  end

  it "places the rear Records title lower in the dark header above the white data body in both locales" do
    [:en, :"zh-CN"].each do |locale|
      I18n.with_locale(locale) do
        fragment = render_inline(described_class.new(src: "/site-images/anysys/anysys-records-forms.svg"))

        expect_nameplate(fragment, label: locale == :en ? "Records" : "记录", plate: [353, 302, 470, 59], text: [365, 351, 64], fill: "#493481", text_fill: "#FFFFFF")
      end
    end
  end

  it "uses the larger AI text inside its scaled and rotated foreground form" do
    fragment = render_inline(described_class.new(src: "/site-images/anysys/anysys-ai-draft.svg"))

    expect_nameplate(fragment, label: "Draft", plate: [741, 482, 280, 64], text: [750, 541, 80], fill: "#E9DDF9", text_fill: "#3C286B")
  end

  it "attaches the privacy nameplate to the front glass within its refined scene transform" do
    fragment = render_inline(described_class.new(src: "/site-images/anysys/anysys-local-privacy.svg"))

    expect_nameplate(fragment, label: "Local data", plate: [442, 674, 389, 77], text: [458, 730, 64], fill: "#FAF9FF", text_fill: "#3C286B", radius: 12)
  end

  it "aligns the local desktop heading with the monitor's skewed source coordinates" do
    fragment = render_inline(described_class.new(src: "/site-images/anysys/anysys-local-desktop.svg"))

    expect_nameplate(fragment, label: "Local data", plate: [515, 214, 508, 65], text: [526, 264, 64], fill: "#FAF9FF", text_fill: "#3C286B")
  end

  it "centers the physical drawer nameplate without rotating the drawer front" do
    fragment = render_inline(described_class.new(src: "/site-images/anysys/anysys-record-control.svg"))

    expect_nameplate(fragment, label: "Records", plate: [640, 714, 320, 77], text: [800, 768, 64], fill: "#E0AFAD", text_fill: "#64324E", radius: 17, anchor: "middle")
  end

  it "centers the pricing heading using viewBox units rather than its 2400x1500 file dimensions" do
    fragment = render_inline(described_class.new(src: "/site-images/anysys/anysys-pricing-growth-hero.svg"))

    expect_nameplate(fragment, label: "Plan", plate: [542, 402, 182, 68], text: [633, 459, 72], fill: "#493481", text_fill: "#FFFFFF", anchor: "middle")
  end

  it "paints the contact subjects inside the contrasting conversation headers" do
    fragment = render_inline(described_class.new(src: "/site-images/anysys/anysys-contact-conversation-hero.svg"))

    expect_nameplate(fragment, label: "Idea", plate: [394, 339, 310, 73], text: [403, 394, 72], fill: "#FFE8D9", text_fill: "#64324E")
    expect_nameplate(fragment, label: "Goals", plate: [960, 454, 293, 79], text: [966, 519, 72], fill: "#D9F8ED", text_fill: "#24594F")
  end

  it "recognizes only exact complete bundled paths" do
    [
      nil, "", "anysys-website-draft.svg", "/other/anysys-website-draft.svg",
      "https://cdn.example.org#{src}", "//cdn.example.org#{src}",
      "#{src}?locale=zh-CN", "#{src}#scene", " #{src}", "#{src}\n",
      "/site-images/anysys/anysys-custom.svg", "/site-images/anysys/ANYSYS-website-draft.svg"
    ].each do |path|
      expect(described_class.known?(path)).to be(false), "unexpected known illustration: #{path.inspect}"
    end
  end

  context "through SectionComponent#render_media" do
    def render_section_media(url, heading: "Owner's custom title")
      render_inline(Websites::Sections::SplitImageTextComponent.new(
        props: { "image_url" => url, "heading" => heading }, theme: website_theme
      ))
    end

    it "delegates a known bundled path and retains literal owner copy in either locale" do
      [:en, :"zh-CN"].each do |locale|
        I18n.with_locale(locale) do
          fragment = render_section_media(src)

          expect(fragment.at_css("svg text").text).to eq(locale == :en ? "Draft" : "草稿")
          expect(fragment.at_css("img")["alt"]).to eq("Owner's custom title")
          expect(fragment.at_css("h2").text).to eq("Owner's custom title")
          expect(fragment.at_css("img")["loading"]).to eq("lazy")
        end
      end
    end

    it "preserves eager native loading for a centered hero" do
      fragment = render_inline(Websites::Sections::HeroCenteredComponent.new(
        props: { "image_url" => src, "headline" => "Owner's hero title" }, theme: website_theme
      ))

      expect(fragment.css("svg text").map(&:text)).to eq(["Draft"])
      expect(fragment.at_css("img")["loading"]).to eq("eager")
      expect(fragment.at_css("img")["alt"]).to eq("Owner's hero title")
    end

    it "leaves valid custom images and remote lookalike filenames as native images" do
      [
        "https://cdn.example.org#{src}?version=1#image",
        "https://cdn.example.org/photo.jpg",
        "/81721200/site/media/custom-photo",
        "/site-images/anysys/anysys-custom.svg"
      ].each do |path|
        fragment = render_section_media(path)

        expect(fragment.css("svg")).to be_empty
        expect(fragment.css("img").size).to eq(1)
        expect(fragment.at_css("img")["src"]).to eq(path)
        expect(fragment.at_css("img")["alt"]).to eq("Owner's custom title")
        expect(fragment.at_css("img")["class"].split).to include("absolute", "inset-0", "size-full", "object-cover")
      end
    end

    it "keeps media validation and rejects encoded, traversal and suffixed bundled-path variants" do
      [
        nil, "", "#{src}?locale=zh-CN", "#{src}#scene", "javascript:alert(1)",
        "data:image/svg+xml,<svg/>", "//cdn.example.org#{src}",
        "/site-images/anysys/../anysys/anysys-website-draft.svg",
        "/site-images/anysys/./anysys-website-draft.svg",
        "/site-images/anysys//anysys-website-draft.svg",
        "/site-images/anysys/%61nysys-website-draft.svg",
        "/site-images/anysys/anysys-website-draft%2esvg",
        "/site-images%2fanysys%2fanysys-website-draft.svg",
        "#{src}%3flocale=en", "#{src}/extra",
        "/site-images/anysys\\anysys-website-draft.svg"
      ].each do |path|
        expect(described_class.known?(path)).to be(false), path.inspect
        fragment = render_section_media(path)

        expect(fragment.css("img, svg")).to be_empty
        expect(page).to have_css("div[aria-hidden='true']", visible: :all)
      end
    end

    it "continues to show assistant-imported photos whole over their blurred background" do
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("photo"), filename: "pet.png", content_type: "image/png", identify: false,
        metadata: { Websites::Activities::ImportMedia::SOURCE_KEY => 1 }
      )
      path = "/81721200/site/media/#{blob.signed_id}"
      fragment = render_section_media(path)

      expect(fragment.css("svg")).to be_empty
      expect(page).to have_css("[data-photo-fit='whole'] img.object-contain[src='#{path}'][alt=\"Owner's custom title\"]")
      expect(page).to have_css("[data-photo-fit='whole'] img.blur-3xl[aria-hidden='true'][alt='']")
    end
  end
end
