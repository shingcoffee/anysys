# frozen_string_literal: true

require "rails_helper"
require "uri"
require "chunky_png"

RSpec.describe CustomerDocs::Repository, "published guides" do
  let(:customer_id) { "81721200" }
  let(:screenshot_subjects) do
    {
      "workspace-help.png" => "getting-started",
      "records-list.png" => "records",
      "forms-publishing.png" => "forms",
      "website-publishing.png" => "websites",
      "email-audience.png" => "email",
      "payment-settings.png" => "payments"
    }
  end

  def pages_for(locale)
    repository = CustomerDocs::Repository.new(customer_id: customer_id, locale: locale)
    CustomerDocs::Catalog.slugs.to_h { |slug| [slug, repository.page(slug)] }
  end

  def screenshot_source_pattern(locale)
    %r{\A/help/docs/screenshots/#{Regexp.escape(locale)}/[a-z0-9]+(?:-[a-z0-9]+)*\.png\z}
  end

  def authored_images(element, parent = nil)
    return [[element, parent]] if element.type == :img

    element.children.flat_map { |child| authored_images(child, element) }
  end

  def markdown_for(locale, slug)
    Rails.root.join("doc/customer", locale, "#{slug}.md").read.sub(/\A---\r?\n.*?\r?\n---\r?\n/m, "")
  end

  def caption_text(figure)
    figure.at_css("figcaption").children.reject { |child| child.name == "a" }.map(&:text).join.strip
  end

  # Compare structure and literal sample inputs, without requiring translated
  # prose or generated heading IDs to match English byte-for-byte.
  def editorial_structure(page, locale)
    sections = []
    Nokogiri::HTML.fragment(page.html).css("h2, h3, code, aside").each do |node|
      case node.name
      when "h2", "h3"
        sections << { level: node.name, examples: [], callouts: [] }
      when "code"
        sections.last.fetch(:examples) << node.text
      when "aside"
        kind = %w[attention note].find do |value|
          node.at_css("p").text == I18n.t("customer_docs.callouts.#{value}", locale: locale)
        end
        expect(kind).to be_present, "unrecognized callout in #{locale}/#{page.slug}.md"
        sections.last.fetch(:callouts) << kind
      end
    end
    sections.each { |section| section.fetch(:examples).sort! }
  end

  CustomerDocs::Catalog::LOCALES.each do |locale|
    context "in #{locale}" do
      it "publishes every guide with localized metadata and the required sections in order" do
        repository = CustomerDocs::Repository.new(customer_id: customer_id, locale: locale)
        required_headings = CustomerDocs::Catalog::REQUIRED_HEADINGS.fetch(locale)

        CustomerDocs::Catalog.slugs.each do |slug|
          path = Rails.root.join("doc/customer", locale, "#{slug}.md")
          expect(path).to be_file, "missing #{locale}/#{slug}.md"
          page = repository.page(slug)
          expect(page).not_to be_nil
          expect(page.title).to be_present
          expect(page.title).not_to eq(slug)
          expect(page.summary).to be_present
          headings = page.headings.select { |heading| heading[:level] == 2 }.map { |heading| heading[:text] }
          expect(headings).to eq(required_headings), "invalid sections in #{locale}/#{slug}.md"
          expect(page.headings.map { |heading| heading[:level] }).to include(3), "missing task headings in #{locale}/#{slug}.md"
          expect(Nokogiri::HTML.fragment(page.html).css("h1")).to be_empty
          expect(page.html).not_to match(/<script|Translation missing:|flowchart/i)
        end
      end

      it "keeps normal links in the customer catalog and permits only figure-owned matching screenshot links" do
        pages = pages_for(locale)

        pages.each do |slug, page|
          expect(page).not_to be_nil, "missing #{locale}/#{slug}.md"
          fragment = Nokogiri::HTML.fragment(page.html)
          fragment.css("a").each do |anchor|
            href = anchor["href"]
            expect(href).to be_present, "invalid link #{anchor.text.inspect} in #{locale}/#{slug}.md"
            if (figure = anchor.ancestors("figure").first)
              expect(href).to match(screenshot_source_pattern(locale)), "invalid screenshot link #{href.inspect} in #{locale}/#{slug}.md"
              expect(figure.css("img").length).to eq(1)
              expect(href).to eq(figure.at_css("img")["src"]), "mismatched screenshot link in #{locale}/#{slug}.md"
              next
            end

            if href.start_with?("#")
              target_page = page
              target_id = href.delete_prefix("#")
            else
              match = href.match(%r{\A/#{customer_id}/admin/help/docs/([^#]+)(?:#(.*))?\z})
              expect(match).not_to be_nil, "non-customer link #{href.inspect} in #{locale}/#{slug}.md"
              expect(CustomerDocs::Catalog.slug?(match[1])).to be(true)
              target_page = pages.fetch(match[1])
              expect(target_page).not_to be_nil, "missing target #{locale}/#{match[1]}.md"
              target_id = match[2]
            end
            next if target_id.blank?

            ids = Nokogiri::HTML.fragment(target_page.html).css("[id]").map { |node| node["id"] }
            expect(ids).to include(URI::DEFAULT_PARSER.unescape(target_id)), "broken section link #{href.inspect} in #{locale}/#{slug}.md"
          end
        end
      end

      it "publishes every authored screenshot as a localized captioned figure with paired native links" do
        pages_for(locale).each do |slug, page|
          aggregate_failures "#{locale}/#{slug}.md" do
            expect(page).not_to be_nil
            document = Kramdown::Document.new(markdown_for(locale, slug), input: "GFM")
            images = authored_images(document.root)
            fragment = Nokogiri::HTML.fragment(page.html)
            figures = fragment.css("figure")
            expect(figures.length).to eq(images.length), "authored screenshots were stripped or extra figures appeared"
            expect(fragment.css("img").length).to eq(figures.length), "images must belong to screenshot figures"

            images.each_with_index do |(authored, parent), index|
              source, alt, caption = authored.attr.values_at("src", "alt", "title")
              expect(parent.type).to eq(:p)
              expect(parent.children).to eq([authored]), "screenshots must be standalone Markdown image paragraphs"
              expect(source).to match(screenshot_source_pattern(locale))
              [alt, caption].each do |text|
                expect(text).to be_present, "screenshot alt and caption must be nonblank"
                expect(text.to_s).to match(locale == "zh-CN" ? /\p{Han}/ : /[A-Za-z]/), "screenshot alt and caption must be localized"
              end

              figure = figures[index]
              expect(figure).not_to be_nil
              next unless figure

              expect(figure.css("img").length).to eq(1)
              image = figure.at_css("img")
              expect(image).not_to be_nil
              next unless image

              expect(image["src"]).to eq(source)
              expect(image["alt"]).to eq(alt)
              expect(image["loading"]).to eq("lazy")
              expect(image["decoding"]).to eq("async")
              expect(figure.css("figcaption").length).to eq(1)
              expect(figure.at_css("figcaption")).not_to be_nil
              next unless figure.at_css("figcaption")

              expect(caption_text(figure)).to eq(caption)
              expect(caption_text(figure)).to be_present
              image_link = figure.at_css("a > img")&.parent
              full_size = figure.at_css("figcaption > a")
              expect(image_link).not_to be_nil
              expect(full_size).not_to be_nil
              expect(figure.css("a").length).to eq(2)
              next unless image_link && full_size

              expect(image_link["aria-label"]).to eq(I18n.t("customer_docs.screenshots.open", caption: caption, locale: locale))
              expect(full_size.text).to eq(I18n.t("customer_docs.screenshots.full_size", locale: locale))
              [image_link, full_size].each do |anchor|
                expect(anchor["href"]).to eq(source)
                expect(anchor.attribute("target")).to be_nil
                expect(anchor.attribute("download")).to be_nil
              end
              expect(figure.css("[style], [srcset], [onclick], [onerror], [data-controller], button")).to be_empty
            end
          end
        end
      end

      it "delivers exactly the six demonstration subjects as real PNGs in their own locale" do
        pages = pages_for(locale)
        sources = pages.values.flat_map { |page| Nokogiri::HTML.fragment(page.html).css("img").map { |image| image["src"] } }
        expected_sources = screenshot_subjects.keys.map { |basename| "/help/docs/screenshots/#{locale}/#{basename}" }
        expect(sources.uniq).to match_array(expected_sources)

        root = Rails.root.join("public/help/docs/screenshots", locale)
        expect(root.glob("*.png").map { |path| path.basename.to_s }).to match_array(screenshot_subjects.keys)
        screenshot_subjects.each do |basename, slug|
          source = "/help/docs/screenshots/#{locale}/#{basename}"
          expect(Nokogiri::HTML.fragment(pages.fetch(slug).html).css("img").map { |image| image["src"] }).to include(source)
          path = root.join(basename)
          expect(path).to be_file, "missing screenshot #{path}"
          image = ChunkyPNG::Image.from_file(path.to_s)
          expect(image.width).to be_positive
          expect(image.height).to be_positive
        end
      end
    end
  end

  it "keeps related-guide targets aligned across both locales" do
    targets = CustomerDocs::Catalog::LOCALES.map do |locale|
      pages_for(locale).transform_values do |page|
        expect(page).not_to be_nil
        Nokogiri::HTML.fragment(page.html).css("a[href]").filter_map do |anchor|
          anchor["href"][/\A\/#{customer_id}\/admin\/help\/docs\/([^#]+)/, 1]
        end.uniq.sort
      end
    end

    expect(targets.first).to eq(targets.last)
  end

  it "keeps bilingual task headings, literal examples, and callout kinds aligned by section" do
    english = pages_for("en")
    chinese = pages_for("zh-CN")

    CustomerDocs::Catalog.slugs.each do |slug|
      aggregate_failures slug do
        expect(chinese.fetch(slug).title).not_to eq(english.fetch(slug).title)
        expect(chinese.fetch(slug).summary).not_to eq(english.fetch(slug).summary)
        expect(editorial_structure(chinese.fetch(slug), "zh-CN"))
          .to eq(editorial_structure(english.fetch(slug), "en")), "heading/example/callout drift in #{slug}.md"
      end
    end
  end

  it "keeps screenshot placement aligned across both locales with translated alt text and captions" do
    figures = CustomerDocs::Catalog::LOCALES.map do |locale|
      pages_for(locale).transform_values do |page|
        Nokogiri::HTML.fragment(page.html).css("figure").map do |figure|
          image = figure.at_css("img")
          { subject: File.basename(image["src"]), alt: image["alt"], caption: caption_text(figure) }
        end
      end
    end

    CustomerDocs::Catalog.slugs.each do |slug|
      english, chinese = figures.map { |pages| pages.fetch(slug) }
      expect(chinese.map { |figure| figure.fetch(:subject) }).to eq(english.map { |figure| figure.fetch(:subject) }), "screenshot subject drift in #{slug}.md"
      english.zip(chinese).each do |first, second|
        expect(second.fetch(:alt)).not_to eq(first.fetch(:alt))
        expect(second.fetch(:caption)).not_to eq(first.fetch(:caption))
      end
    end
  end
end
