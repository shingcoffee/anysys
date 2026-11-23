# frozen_string_literal: true

require "kramdown"
require "kramdown-parser-gfm"
require "loofah"
require "nokogiri"
require "securerandom"

# Turns one reference page into sanitized HTML plus an in-page table of contents.
# Kramdown (GFM) owns Markdown. This class adds callouts, same-page heading
# anchors, slug links, and an allow-list scrub.
module DeveloperDocs
  class Renderer
    CALLOUT_OPEN = /\A:::(attention|note)[ \t]*\r?\n?\z/
    CALLOUT_CLOSE = /\A:::[ \t]*\r?\n?\z/
    FENCE = /\A```/
    PLACEHOLDER = /\ADEVDOCCALLOUT(\d+)END\z/
    CACHE_VERSION = "documentation/v6"
    SCREENSHOT_POLICY_VERSION = "screenshots/v1"
    SCREENSHOT_ROOT = "/help/docs/screenshots"
    SCREENSHOT_SOURCE = %r{\A/help/docs/screenshots/(?:en|zh-CN)/[a-z0-9]+(?:-[a-z0-9]+)*\.png\z}

    ASIDE_CLASS = {
      "attention" => "my-6 rounded-xl border border-warning bg-warning-subtle px-4 py-3.5 text-base leading-normal text-text-primary",
      "note" => "my-6 rounded-xl border border-info bg-info-subtle px-4 py-3.5 text-base leading-normal text-text-primary"
    }.freeze
    LABEL_CLASS = {
      "attention" => "mb-2 text-sm font-semibold leading-normal text-warning",
      "note" => "mb-2 text-sm font-semibold leading-normal text-info"
    }.freeze

    ALLOWED_TAGS = %w[
      h1 h2 h3 h4 h5 h6 p a ul ol li pre code blockquote table thead tbody tr th td
      strong em hr br aside span div dl dt dd
    ].freeze
    SCREENSHOT_TAGS = %w[figure figcaption img].freeze
    ALLOWED_ATTRS = {
      "a" => %w[id href class aria-label].freeze,
      "th" => %w[id class colspan rowspan].freeze,
      "td" => %w[id class colspan rowspan].freeze,
      "img" => %w[src alt loading decoding].freeze,
      "figure" => [].freeze,
      "figcaption" => [].freeze
    }.freeze
    COMMON_ATTRS = %w[id class].freeze

    DOCUMENT_OPTIONS = {
      input: "GFM",
      auto_ids: true,
      hard_wrap: false,
      syntax_highlighter: :tailwind_rouge,
      syntax_highlighter_opts: {}
    }.freeze

    class Error < StandardError; end

    Result = Data.define(:html, :headings)

    def self.call(markdown, link_resolver:, labels:, anchor_label:, catalog: Catalog,
                  screenshot_root: nil, screenshot_labels: nil)
      new(markdown, link_resolver:, labels:, anchor_label:, catalog:, screenshot_root:, screenshot_labels:).call
    end

    def initialize(markdown, link_resolver:, labels:, anchor_label:, catalog: Catalog,
                   screenshot_root: nil, screenshot_labels: nil)
      unless screenshot_root.nil? || screenshot_root == SCREENSHOT_ROOT
        raise ArgumentError, "unsupported documentation screenshot root"
      end
      if screenshot_root && (!screenshot_labels.is_a?(Hash) || !%i[full_size open].all? { |key| screenshot_labels[key].present? })
        raise ArgumentError, "screenshot_labels must provide localized full_size and open labels"
      end
      @markdown = markdown.to_s.gsub("\r\n", "\n")
      @catalog = catalog
      @link_resolver = link_resolver
      @labels = labels
      @anchor_label = anchor_label
      @screenshot_root = screenshot_root
      @screenshot_labels = screenshot_labels
      @screenshots = {}
      @screenshot_token = "DEV DOC SCREENSHOT #{SecureRandom.hex(16)}"
    end

    def call
      Highlighter.install!
      body, callouts = extract_callouts(@markdown)
      document = Kramdown::Document.new(body, DOCUMENT_OPTIONS)
      headings = extract_headings(document.root)
      extract_screenshots(document.root) if @screenshot_root
      html = replace_callouts(document.to_html, callouts)
      fragment = Nokogiri::HTML5.fragment(html)
      rewrite_links(fragment)
      decorate_headings(fragment)
      if @screenshot_root
        # Only Markdown images recorded from Kramdown's AST can become figures.
        # Raw HTML images always fall back to text, regardless of their source.
        fragment.css("img").each { |image| replace_with_alt(image) }
        insert_screenshots(fragment)
      end
      Result.new(html: sanitize(fragment).html_safe, headings: headings)
    end

    private

    def extract_callouts(markdown)
      lines = markdown.lines
      output = []
      callouts = []
      index = 0
      while index < lines.length
        line = lines[index]
        if line.match?(FENCE)
          output << line
          index += 1
          while index < lines.length && !lines[index].match?(FENCE)
            output << lines[index]
            index += 1
          end
          output << lines[index] if index < lines.length
          index += 1
          next
        end

        if (match = line.match(CALLOUT_OPEN))
          kind = match[1]
          index += 1
          body_lines = []
          while index < lines.length && !lines[index].match?(CALLOUT_CLOSE)
            body_lines << lines[index]
            index += 1
          end
          index += 1 if index < lines.length
          token = "DEVDOCCALLOUT#{callouts.length}END"
          callouts << { token: token, kind: kind, body: body_lines.join }
          output << "\n\n#{token}\n\n"
          next
        end

        output << line
        index += 1
      end
      [output.join, callouts]
    end

    def extract_headings(element, headings = [])
      if element.type == :header
        level = element.options[:level].to_i
        if level.between?(2, 3)
          text = plain_text(element).squish
          if text.present?
            id = element.attr["id"].to_s.presence || unique_id(text, headings)
            element.attr["id"] = id
            headings << { level: level, id: id, text: text }
          end
        end
      end
      element.children.each { |child| extract_headings(child, headings) }
      headings
    end

    def unique_id(text, headings)
      base = text.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
      base = "section" if base.blank?
      taken = headings.map { |heading| heading[:id] }
      candidate = base
      suffix = 2
      while taken.include?(candidate)
        candidate = "#{base}-#{suffix}"
        suffix += 1
      end
      candidate
    end

    def plain_text(element)
      return element.value.to_s if element.type == :text

      element.children.map { |child| plain_text(child) }.join
    end

    def replace_callouts(html, callouts)
      callouts.each do |callout|
        document = Kramdown::Document.new(callout[:body], DOCUMENT_OPTIONS)
        extract_screenshots(document.root) if @screenshot_root
        inner = document.to_html
        aside = aside_html(callout[:kind], inner)
        pattern = %r{<p>\s*#{Regexp.escape(callout[:token])}\s*</p>}
        replaced = html.sub(pattern, aside)
        if replaced == html
          raise Error, "callout placeholder #{callout[:token]} was not rendered as its own paragraph"
        end
        html = replaced
      end
      html
    end

    def aside_html(kind, inner)
      label = ERB::Util.html_escape(@labels.fetch(kind))
      %(<aside class="#{ASIDE_CLASS.fetch(kind)}"><p class="#{LABEL_CLASS.fetch(kind)}">#{label}</p>#{inner}</aside>)
    end

    def extract_screenshots(element)
      if element.type == :p && element.children.length == 1 && element.children.first.type == :img
        image = element.children.first
        source, alt, caption = image.attr.values_at("src", "alt", "title")
        if safe_screenshot_source?(source.to_s) && alt.present? && caption.present?
          token = "#{@screenshot_token} #{@screenshots.length}"
          @screenshots[token] = { source: source, alt: alt, caption: caption }
          element.attr.clear
          element.children.replace([Kramdown::Element.new(:text, token)])
          return
        end
      end

      # Reject inline, untitled, or unsafe Markdown images before HTML conversion
      # can normalize/escape their source. Preserve alt as escaped plain text.
      element.children.map! do |child|
        if child.type == :img
          Kramdown::Element.new(:text, child.attr["alt"].to_s)
        elsif child.type == :a && contains_image?(child)
          Kramdown::Element.new(:text, image_alt_text(child))
        else
          extract_screenshots(child)
          child
        end
      end
    end

    def contains_image?(element)
      element.type == :img || element.children.any? { |child| contains_image?(child) }
    end

    def image_alt_text(element)
      return element.attr["alt"].to_s if element.type == :img
      return element.value.to_s if element.type == :text

      element.children.map { |child| image_alt_text(child) }.join
    end

    def insert_screenshots(fragment)
      fragment.css("p").each do |paragraph|
        screenshot = @screenshots[paragraph.text]
        next unless screenshot

        source, alt, caption = screenshot.values_at(:source, :alt, :caption)
        next unless safe_screenshot_source?(source)

        figure = Nokogiri::XML::Node.new("figure", fragment.document)
        image_link = Nokogiri::XML::Node.new("a", fragment.document)
        image_link["href"] = source
        image_link["aria-label"] = format(@screenshot_labels.fetch(:open), caption: caption)
        image = Nokogiri::XML::Node.new("img", fragment.document)
        image["src"] = source
        image["alt"] = alt
        image["loading"] = "lazy"
        image["decoding"] = "async"
        image_link.add_child(image)
        figure.add_child(image_link)

        figcaption = Nokogiri::XML::Node.new("figcaption", fragment.document)
        text = Nokogiri::XML::Node.new("span", fragment.document)
        text.content = caption
        figcaption.add_child(text)
        full_size = Nokogiri::XML::Node.new("a", fragment.document)
        full_size["href"] = source
        full_size.content = @screenshot_labels.fetch(:full_size)
        figcaption.add_child(full_size)
        figure.add_child(figcaption)
        paragraph.replace(figure)
      end
    end

    def replace_with_alt(image)
      image.ancestors("a").each { |anchor| anchor.replace(anchor.children) }
      image.replace(Nokogiri::XML::Text.new(image["alt"].to_s, image.document))
    end

    def rewrite_links(fragment)
      fragment.css("a[href]").each do |anchor|
        rewritten = rewrite_href(anchor["href"].to_s)
        if rewritten
          anchor["href"] = rewritten
        else
          anchor.remove_attribute("href")
        end
      end
    end

    def rewrite_href(href)
      return href if safe_external?(href)
      return href if href.start_with?("#") && safe_fragment?(href)

      path, fragment = href.split("#", 2)
      slug = path.to_s.sub(%r{\A\./}, "").sub(/\.md\z/, "")
      return nil unless @catalog.slug?(slug)

      resolved = @link_resolver.call(slug)
      return nil if resolved.blank?

      fragment.present? ? "#{resolved}##{fragment}" : resolved
    end

    def decorate_headings(fragment)
      fragment.css("h2, h3, h4").each do |node|
        next if node["id"].blank?

        node["class"] = [node["class"], "group scroll-mt-28"].compact.join(" ")
        link = Nokogiri::XML::Node.new("a", fragment.document)
        link["href"] = "##{node["id"]}"
        link["class"] = "ml-2 text-base font-normal text-text-muted no-underline opacity-0 group-hover:opacity-100 focus:opacity-100"
        link["aria-label"] = @anchor_label
        link.content = "#"
        node.add_child(link)
      end
    end

    def sanitize(fragment)
      # Nokogiri's HTML5 fragment has no scrub!; Loofah's fragment does.
      cleaned = Loofah.fragment(fragment.to_html)
      cleaned.scrub!(scrubber)
      cleaned.to_html
    end

    def scrubber
      Loofah::Scrubber.new do |node|
        next Loofah::Scrubber::CONTINUE unless node.element?
        if node.name == "img" && @screenshot_root && !safe_screenshot_source?(node["src"].to_s)
          replace_with_alt(node)
          next Loofah::Scrubber::STOP
        end
        unless ALLOWED_TAGS.include?(node.name) || (@screenshot_root && SCREENSHOT_TAGS.include?(node.name))
          node.remove
          next Loofah::Scrubber::STOP
        end

        node.attribute_nodes.each do |attr|
          if !ALLOWED_ATTRS.fetch(node.name, COMMON_ATTRS).include?(attr.name)
            attr.remove
          elsif attr.name == "href" && !safe_node_href?(node, attr.value)
            attr.remove
          elsif attr.name == "loading" && attr.value != "lazy"
            attr.remove
          elsif attr.name == "decoding" && attr.value != "async"
            attr.remove
          elsif %w[colspan rowspan].include?(attr.name) && !attr.value.match?(/\A[1-9]\d*\z/)
            attr.remove
          end
        end
        Loofah::Scrubber::CONTINUE
      end
    end

    def safe_screenshot_source?(value)
      @screenshot_root == SCREENSHOT_ROOT && value.match?(SCREENSHOT_SOURCE)
    end

    def safe_node_href?(node, value)
      if node.ancestors.any? { |ancestor| ancestor.name == "figure" }
        safe_screenshot_source?(value)
      elsif value.start_with?(SCREENSHOT_ROOT)
        false
      else
        safe_href?(value)
      end
    end

    def safe_href?(value)
      safe_external?(value) || (value.start_with?("#") && safe_fragment?(value)) || safe_path?(value)
    end

    def safe_external?(value)
      value.match?(%r{\Ahttps?://}i) && safe_fragment?(value)
    end

    def safe_path?(value)
      value.start_with?("/") && !value.start_with?("//") && safe_fragment?(value)
    end

    def safe_fragment?(value)
      !value.match?(/[\s"'<>]/)
    end
  end
end
