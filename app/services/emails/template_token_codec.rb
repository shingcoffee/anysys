# frozen_string_literal: true

require "nokogiri"

module Emails
  # Converts between stored `{{uuid}}` tokens and editor presentation forms.
  #
  # Editor presentation (rich text, subject, plain text, code HTML):
  #   {{Human readable label}}
  #
  # Legacy chip markup is still accepted on the way into storage:
  #   <span class="email-token-chip" data-email-token-uuid="..." ...>Label</span>
  #
  # Storage / send path always uses `{{uuid}}`.
  class TemplateTokenCodec
    CHIP_CLASS = "email-token-chip"
    CHIP_CLASSES = "email-token-chip inline-flex items-center rounded border border-accent-muted bg-accent-subtle px-1.5 py-0.5 text-sm font-medium text-accent-text"
    UUID_RE = TokenCatalog::TOKEN_UUID
    TOKEN_INNER_RE = /\{\{\s*([^}]+?)\s*\}\}/
    UUID_TOKEN_RE = /\A(#{UUID_RE})(?:\|fallback:"([^"]*)")?\z/io

    class << self
      def chips_to_tokens(html, format: :html)
        return "" if html.blank?

        doc = Nokogiri::HTML::DocumentFragment.parse(html.to_s)
        doc.css("span.#{CHIP_CLASS}[data-email-token-uuid]").each do |node|
          uuid = node["data-email-token-uuid"].to_s
          fallback = node["data-email-token-fallback"]
          node.replace(Nokogiri::XML::Text.new(token_with_optional_fallback(uuid, fallback), doc))
        end
        format == :html ? doc.to_html : doc.text
      end

      def tokens_to_chips(text, customer_id:)
        return "" if text.blank?

        catalog = TokenCatalog.for_customer(customer_id)
        text.to_s.gsub(/\{\{(#{UUID_RE})(?:\|fallback:"([^"]*)")?\}\}/i) do
          uuid = Regexp.last_match(1)
          fallback = Regexp.last_match(2)
          token = catalog.find_by_uuid(uuid)
          label = token ? catalog.editor_label(token) : unknown_label
          chip_html(uuid, label, fallback: fallback)
        end
      end

      # Editor plain-text display: {{uuid}} → {{Label}} (never exposes the UUID).
      # Callers pass a shared TokenCatalog (one per request/render) — building
      # a catalog per call would re-query the token tables for every row.
      def tokens_to_labels(text, catalog:)
        return "" if text.blank?

        text.to_s.gsub(/\{\{(#{UUID_RE})(?:\|fallback:"([^"]*)")?\}\}/i) do
          uuid = Regexp.last_match(1)
          fallback = Regexp.last_match(2)
          token = catalog.find_by_uuid(uuid)
          label = token ? catalog.editor_label(token) : unknown_label
          token_with_optional_fallback(label, fallback)
        end
      end

      # Persist plain-text editor labels: {{Label}} → {{uuid}}
      # Preserves optional `|fallback:"..."` suffixes through the rewrite.
      def labels_to_tokens(text, customer_id:)
        return "" if text.blank?

        by_label = TokenCatalog.for_customer(customer_id).label_index
        text.to_s.gsub(TOKEN_INNER_RE) do
          inner = Regexp.last_match(1).to_s
          if (m = inner.match(UUID_TOKEN_RE))
            token_with_optional_fallback(m[1], m[2])
          else
            label = inner.sub(/\s*\|fallback:".*"\z/, "").strip
            fallback = inner[/\|\s*fallback:"([^"]*)"\s*\z/, 1]
            uuid = by_label[label.downcase]
            uuid ? token_with_optional_fallback(uuid, fallback) : "{{#{inner}}}"
          end
        end
      end

      def normalize_for_storage(text, customer_id:, format: :text)
        return "" if text.blank?

        source = if format == :html || text.to_s.match?(/<span\b[^>]*\bdata-email-token-uuid=/i)
                   chips_to_tokens(text, format: format)
                 else
                   text.to_s
                 end
        labels_to_tokens(source, customer_id: customer_id)
      end

      def chip_html(uuid, label, fallback: nil)
        fallback_attribute = fallback.nil? ? "" : %( data-email-token-fallback="#{ERB::Util.html_escape(fallback)}")
        %(<span class="#{CHIP_CLASSES}" data-email-token-uuid="#{ERB::Util.html_escape(uuid)}"#{fallback_attribute} contenteditable="false">#{ERB::Util.html_escape(label)}</span>)
      end

      private

      def unknown_label
        I18n.t("email.template_tokens.unknown_label")
      end

      def token_with_optional_fallback(uuid, fallback)
        if fallback.nil?
          "{{#{uuid}}}"
        else
          "{{#{uuid}|fallback:\"#{fallback}\"}}"
        end
      end
    end
  end
end
