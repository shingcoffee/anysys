# frozen_string_literal: true

module Emails
  # Single author-facing preview pipeline for templates.
  #
  # Modes:
  #   :tokens — compile + cid→blob + {{Label}} display (no sample fill)
  #   :sample — interpolate with vars (editor live preview / test render)
  #
  # Returns subject/body_html/body_text plus body_srcdoc (document-wrapped HTML
  # for iframes). Does not persist changes to the template.
  class AuthorPreview
    MODES = %i[tokens sample].freeze

    class << self
      # @param template [Emails::Template]
      # @param mode [Symbol] :tokens | :sample
      # @param catalog [Emails::TokenCatalog, nil] required for :tokens (built if omitted)
      # @param vars [Hash, nil] sample variables for :sample (VariableContext if omitted)
      # @param user [User, nil] used to build default sample vars when vars blank
      # @return [Hash] keys: :subject, :body_html, :body_text, :body_srcdoc
      def call(template, mode: :tokens, catalog: nil, vars: nil, user: nil)
        mode = mode.to_sym
        raise ArgumentError, "unknown mode: #{mode}" unless MODES.include?(mode)

        case mode
        when :tokens then tokens_preview(template, catalog: catalog)
        when :sample then sample_preview(template, vars: vars, user: user)
        end
      end

      private

      def tokens_preview(template, catalog:)
        catalog ||= TokenCatalog.for_customer(template.customer_id)
        subject = TemplateTokenCodec.tokens_to_labels(template.subject, catalog: catalog)
        body_html = CompileTemplate.cids_to_blob_urls(
          CompileTemplate.call(template),
          customer_id: template.customer_id
        )
        body_html = TemplateTokenCodec.tokens_to_labels(body_html, catalog: catalog)
        # Keep stored plain-text only — do not invent a strip_html fallback so
        # the detail/preview UI can still show the "no fallback" empty state.
        body_text = TemplateTokenCodec.tokens_to_labels(template.body_text.to_s, catalog: catalog)
        pack(subject, body_html, body_text)
      end

      def sample_preview(template, vars:, user:)
        vars ||= VariableContext.for(user: user) if user
        vars ||= {}
        rendered = TemplateRenderer.render(
          template:   template,
          vars:       vars,
          tracking:   false,
          message_id: SecureRandom.uuid
        )
        body_html = CompileTemplate.cids_to_blob_urls(
          rendered[:body_html],
          customer_id: template.customer_id
        )
        pack(rendered[:subject], body_html, rendered[:body_text])
      end

      def pack(subject, body_html, body_text)
        {
          subject:     subject.to_s,
          body_html:   body_html.to_s,
          body_text:   body_text.to_s,
          body_srcdoc: CompileTemplate.wrap_for_browser(body_html).to_s
        }
      end
    end
  end
end
