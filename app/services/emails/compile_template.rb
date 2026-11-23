# frozen_string_literal: true

require "nokogiri"

module Emails
  # Save-time / unsaved-preview sync: ActionText content fragment → email
  # `body_html`. Owned by Emails::Template#sync_body_html! so preview, test
  # send, and persistence share one path (no divergent compilers).
  #
  # For `rich_text` templates:
  #   1. Reads the ActionText fragment (`body.body.to_html`) — never
  #      RichText#to_s, which wraps layout chrome (`trix-content` / ERB comments).
  #   2. Rewrites image <action-text-attachment> nodes to
  #      <img src="cid:blob-<id>"> once here (DeliveryMailer inlines those blobs).
  #   3. Leaves {{...}} tokens for Emails::TemplateRenderer.
  #
  # For `code` templates:
  #   Returns `template.body_html` unchanged (the author controls the HTML).
  #
  # Usage:
  #   html = Emails::CompileTemplate.call(template)
  #   ids  = Emails::CompileTemplate.blob_ids_for(template)
  class CompileTemplate
    # Lexxy serializes text/background highlights as CSS variables
    # (`color: var(--highlight-3)`). Those variables are defined only by
    # Lexxy's own stylesheet, which neither email clients nor the author
    # preview iframe load — highlighted text would silently render uncolored
    # for recipients. Resolve them to the concrete values from the gem's
    # lexxy-variables.css here, at the single email-safe compile boundary.
    LEXXY_HIGHLIGHT_VALUES = {
      "--highlight-1"    => "rgb(136, 118, 38)",
      "--highlight-2"    => "rgb(185, 94, 6)",
      "--highlight-3"    => "rgb(207, 0, 0)",
      "--highlight-4"    => "rgb(216, 28, 170)",
      "--highlight-5"    => "rgb(144, 19, 254)",
      "--highlight-6"    => "rgb(5, 98, 185)",
      "--highlight-7"    => "rgb(17, 138, 15)",
      "--highlight-8"    => "rgb(148, 82, 22)",
      "--highlight-9"    => "rgb(102, 102, 102)",
      "--highlight-bg-1" => "rgba(229, 223, 6, 0.3)",
      "--highlight-bg-2" => "rgba(255, 185, 87, 0.3)",
      "--highlight-bg-3" => "rgba(255, 118, 118, 0.3)",
      "--highlight-bg-4" => "rgba(248, 137, 216, 0.3)",
      "--highlight-bg-5" => "rgba(190, 165, 255, 0.3)",
      "--highlight-bg-6" => "rgba(124, 192, 252, 0.3)",
      "--highlight-bg-7" => "rgba(140, 255, 129, 0.3)",
      "--highlight-bg-8" => "rgba(221, 170, 123, 0.3)",
      "--highlight-bg-9" => "rgba(200, 200, 200, 0.3)"
    }.freeze

    # Lexxy tables get their chrome (borders, header background, cell
    # padding) from the gem's stylesheet, which neither email clients nor
    # the author preview iframe load — a table would render as a borderless
    # grid for recipients. Inline the equivalents here, at the same compile
    # boundary as the highlight resolution above. Gray values mirror the
    # gem's lexxy-variables.css (oklch 85% / 96%).
    TABLE_STYLE = "border-collapse: collapse; width: 100%;".freeze
    TABLE_CELL_STYLE = "border: 1px solid #cecece; padding: 8px; text-align: left;".freeze
    TABLE_HEADER_CELL_STYLE = "#{TABLE_CELL_STYLE} background-color: #f2f2f2; font-weight: bold;".freeze
    TABLE_HEADER_CELL_CLASS = "lexxy-content__table-cell--header".freeze

    # @param template [Emails::Template]
    # @return [String] email-safe HTML
    def self.call(template)
      new(template).compile
    end

    # Browser-facing companion to the cid: rewriting in #rewrite_attachments:
    # the author preview (iframe / full-page) renders body_html in a browser,
    # which cannot load cid: URLs — only the mailer's inline MIME parts can.
    # Swap cid sources for app-relative blob URLs so preview images render.
    # Blobs are tenant-scoped: a foreign cid:blob-<id> stays as cid: so
    # preview cannot mint a signed URL for another customer's file.
    def self.cids_to_blob_urls(html, customer_id:)
      return html if html.blank?

      html.gsub(/cid:blob-(\d+)/) do |match|
        blob = ActiveStorage::Blob.for_customer(customer_id).find_by(id: Regexp.last_match(1))
        blob ? Rails.application.routes.url_helpers.rails_blob_url(blob, only_path: true) : match
      end
    end

    # Wrap a body fragment so an author-facing iframe srcdoc has a real document
    # shell (charset + readable defaults). Mirrors the Stimulus preview
    # controllers' wrapContent — keep the CSS in sync with those.
    def self.wrap_for_browser(html)
      return html if html.blank?

      <<~HTML.strip
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 16px; line-height: 1.5; }
            img { max-width: 100%; height: auto; }
          </style>
        </head>
        <body>#{html}</body>
        </html>
      HTML
    end

    # Author-facing browser HTML for detail/preview iframes: recompile from the
    # template's source of truth (ActionText for rich_text), swap cid: images
    # for blob URLs, and wrap in a document shell. Does not mutate the record.
    def self.for_browser(template)
      wrap_for_browser(cids_to_blob_urls(call(template), customer_id: template.customer_id))
    end

    # Returns the ActiveStorage::Blob ids referenced as inline attachments in
    # the template's rich-text body. Used by the SMTP adapter to attach inline
    # CID parts to the outgoing mail.
    #
    # @param template [Emails::Template]
    # @return [Array<Integer>]
    def self.blob_ids_for(template)
      new(template).blob_ids
    end

    # -------------------------------------------------------------------------

    def initialize(template)
      @template = template
    end

    def compile
      if @template.editor_type != "rich_text"
        return TemplateTokenCodec.normalize_for_storage(
          @template.body_html,
          customer_id: @template.customer_id,
          format: :html
        )
      end
      return "" if @template.body.blank?

      TemplateTokenCodec.normalize_for_storage(
        resolve_highlight_vars(email_safe_fragment(raw_html)),
        customer_id: @template.customer_id,
        format: :html
      )
    end

    def blob_ids
      return [] if @template.editor_type != "rich_text"
      return [] if @template.body.blank?

      body_content = @template.body.body
      return [] unless body_content

      body_content.attachables.filter_map do |attachable|
        attachable.id if attachable.is_a?(ActiveStorage::Blob)
      end
    end

    private

    # Prefer the ActionText content fragment (matches Lexxy/editor HTML) over
    # RichText#to_s, which wraps content in the ActionText layout
    # (`trix-content` + ERB debug comments) and makes preview diverge from
    # what the author sees in the editor.
    def raw_html
      content = @template.body&.body
      return "" unless content

      content.to_html.to_s
    end

    # Parse once, then apply the email-safe transforms that need the DOM:
    # attachment rewriting and table styling.
    def email_safe_fragment(html)
      return html if html.blank?

      doc = Nokogiri::HTML5.fragment(html)
      rewrite_attachments(doc)
      style_tables(doc)
      doc.to_html
    end

    # Find all <action-text-attachment> nodes that wrap image blobs and
    # replace them with a simple <img src="cid:blob-<id>">.
    # Non-image attachments are left as-is so text/file attachments render
    # their description.
    def rewrite_attachments(doc)
      doc.css("action-text-attachment").each do |node|
        blob_id = blob_id_from_node(node)
        next unless blob_id

        img = Nokogiri::XML::Node.new("img", doc)
        img["src"] = "cid:blob-#{blob_id}"
        img["alt"]  = node["filename"] || "image"
        node.replace(img)
      end
    end

    def style_tables(doc)
      doc.css("table").each do |table|
        table["style"] = merge_style(table["style"], TABLE_STYLE)
        table.css("th, td").each do |cell|
          base = cell["class"].to_s.include?(TABLE_HEADER_CELL_CLASS) ? TABLE_HEADER_CELL_STYLE : TABLE_CELL_STYLE
          cell["style"] = merge_style(cell["style"], base)
        end
      end
    end

    def merge_style(existing, addition)
      parts = [existing, addition].flat_map { |s| s.to_s.split(";").map(&:strip) }.reject(&:empty?)
      return "" if parts.empty?

      "#{parts.join("; ")};"
    end

    def resolve_highlight_vars(html)
      html.gsub(/var\(\s*(--highlight(?:-bg)?-\d)\s*\)/) do |match|
        LEXXY_HIGHLIGHT_VALUES.fetch(Regexp.last_match(1), match)
      end
    end

    # Extract the blob id from an <action-text-attachment> node.
    # The node carries a `sgid` attribute which is a GlobalID signed URL for
    # an ActiveStorage::Blob. We locate the blob by resolving the sgid so that
    # the mapping is accurate even if ids differ across environments.
    def blob_id_from_node(node)
      sgid = node["sgid"]
      return nil unless sgid.present?

      # Only rewrite image content-types (skip file attachments)
      content_type = node["content-type"].to_s
      return nil unless content_type.start_with?("image/")

      blob = GlobalID::Locator.locate_signed(sgid, for: "attachable")
      blob.is_a?(ActiveStorage::Blob) ? blob.id : nil
    rescue StandardError
      nil
    end
  end
end
