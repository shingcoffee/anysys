# frozen_string_literal: true

require "nokogiri"
require "uri"

module Emails
  class TemplateRenderer
    class << self
      def render(template:, vars:, tracking: false, message_id: nil, customer_id: nil, message: nil)
        cid = message&.customer_id || customer_id || template.customer_id
        if message&.message_type.to_s == "campaign"
          vars = vars.to_h.except(:unsubscribe_url, "unsubscribe_url").merge(
            "unsubscribe_url" => SendActivities::SendActivityUnsubscribe.url_for_message(message)
          )
        end
        catalog = TokenCatalog.for_customer(cid)
        resolved = catalog.resolve_vars(vars)

        # Editor may send human {{Label}} tokens; storage/send always uses {{uuid}}.
        subject = interpolate(
          TemplateTokenCodec.normalize_for_storage(template.subject, customer_id: cid),
          resolved
        )
        # HTML-escape interpolated VALUES in the HTML body so a variable that
        # happens to contain markup (links, hidden divs, tracking pixels) is
        # rendered as inert text, not live HTML — the template author's own
        # HTML stays intact. The plain-text body derives from an UNescaped
        # interpolation so entities don't leak into it.
        #
        # Compile fresh rather than trusting the cached body_html column:
        # rich_text templates derive email-safe HTML (cid images, inlined
        # Lexxy table/highlight styles) from ActionText, and CompileTemplate
        # is a no-op normalize for code templates. Avoids sending/showing
        # bodies compiled before those transforms existed.
        body_source = CompileTemplate.call(template)
        body_html = interpolate(body_source, resolved, escape: :html)

        if tracking && message_id.present?
          body_html = inject_tracking(body_html, message_id)
        end

        body_text = if template.body_text.present?
                      interpolate(
                        TemplateTokenCodec.normalize_for_storage(template.body_text, customer_id: cid),
                        resolved
                      )
        else
                      strip_html(interpolate(body_source, resolved))
        end

        { subject: subject, body_html: body_html, body_text: body_text }
      end

      def inject_tracking(html, message_id)
        return html if html.blank?

        doc = Nokogiri::HTML::DocumentFragment.parse(html)

        url_options = (ActionMailer::Base.default_url_options || {}).symbolize_keys
        url_options[:host] ||= "localhost"

        routes = Rails.application.routes.url_helpers

        # Rewrite links
        doc.css("a[href]").each do |a|
          href = a["href"].to_s
          next if href.start_with?("mailto:") || href.include?("/email/track/#{message_id}/click")
          next if href.include?("/unsubscribe/")
          next unless http_href?(href)

          verifier = Rails.application.message_verifier(:email_tracking)
          sig = verifier.generate({ message_id: message_id, url: href })

          a["href"] = routes.email_track_click_url(
            message_id: message_id,
            url: href,
            sig: sig,
            **url_options
          )
        end

        # Add open pixel once. DeliverMessageJob retries while still queued and
        # would otherwise append another pixel on every attempt.
        pixel_path = "/email/track/#{message_id}/open"
        unless doc.css("img[src]").any? { |img| img["src"].to_s.include?(pixel_path) }
          verifier = Rails.application.message_verifier(:email_tracking)
          sig = verifier.generate(message_id)

          pixel_url = routes.email_track_open_url(
            message_id: message_id,
            sig: sig,
            **url_options
          )
          pixel_tag = "<img src=\"#{pixel_url}\" width=\"1\" height=\"1\" alt=\"\" />"

          if doc.at_css("body")
            doc.at_css("body").add_child(pixel_tag)
          else
            doc.add_child(pixel_tag)
          end
        end

        doc.to_html
      end

      def interpolate(text, vars, escape: nil)
        return "" if text.blank?

        text.to_s.gsub(/\{\{(#{TokenCatalog::TOKEN_UUID})(?:\|fallback:"([^"]*)")?\}\}/i) do
          uuid = Regexp.last_match(1)
          fallback = Regexp.last_match(2)
          value = resolve_value(uuid, vars)
          value = value.blank? && fallback ? fallback : value.to_s
          escape == :html ? ERB::Util.html_escape(value) : value
        end
      end

      def strip_html(html)
        ActionController::Base.helpers.strip_tags(html.to_s)
      end

      private

      def resolve_value(uuid, vars)
        return nil unless vars.is_a?(Hash)

        vars[uuid] || vars[uuid.to_s] || vars[uuid.to_s.downcase]
      end

      def http_href?(href)
        uri = URI.parse(href.to_s)
        uri.is_a?(URI::HTTP) && uri.userinfo.blank? && uri.host.present?
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
