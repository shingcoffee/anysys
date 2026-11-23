# frozen_string_literal: true

module Mailers
  # Shared HTML chrome for platform-sent transactional mail (auth, MFA,
  # billing). Table layout and inline styles are not a Tailwind violation:
  # mail clients strip <style> blocks and never load the app CSS bundle.
  #
  # Warm editorial direction: cream canvas, ivory card, Georgia serif
  # headline, bronze accents. Billing notices add a receipt block and a
  # fact table inside the same chrome.
  class ShellComponent < ApplicationComponent
    Fact = Struct.new(:label, :value, :emphasize, keyword_init: true)

    SANS = "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif"
    SERIF = "Georgia,'Times New Roman',Times,serif"

    # @param preheader [String] hidden inbox-preview text
    # @param brand [String] wordmark
    # @param heading [String] small kicker above the headline
    # @param title [String] short headline — never the recipient address
    # @param body [String] supporting paragraph
    # @param footer [String] sender line under the card
    # @param greeting [String, nil] personalized line under the headline
    # @param ignore [String, nil] "if you didn't request this" line
    # @param note [String, nil] extra paragraph after the CTA / facts
    # @param action [String, nil] CTA label
    # @param action_url [String, nil] absolute URL for the button and fallback
    # @param fallback [String, nil] copy above the printed URL
    # @param facts [Array<Hash, Fact>] labeled rows for billing receipts
    # @param highlight [String, nil] large featured value (usually an amount)
    # @param highlight_caption [String, nil] label above the highlight
    def initialize(
      preheader:, brand:, heading:, title:, body:, footer:,
      greeting: nil, ignore: nil, note: nil,
      action: nil, action_url: nil, fallback: nil,
      facts: [], highlight: nil, highlight_caption: nil
    )
      @preheader = preheader
      @brand = brand
      @heading = heading
      @title = title
      @body = body
      @footer = footer
      @greeting = greeting
      @ignore = ignore
      @note = note
      @action = action
      @action_url = action_url
      @fallback = fallback
      @highlight = highlight
      @highlight_caption = highlight_caption
      @facts = Array(facts).map { |fact| coerce_fact(fact) }
    end

    attr_reader :preheader, :brand, :heading, :title, :body, :footer,
                :greeting, :ignore, :note, :action, :action_url, :fallback,
                :facts, :highlight, :highlight_caption

    def action?
      action.present? && action_url.present?
    end

    def facts?
      facts.any?
    end

    def highlight?
      highlight.present?
    end

    def greeting?
      greeting.present?
    end

    def display_value(value)
      value.presence || I18n.t("mailers.shell.blank_value")
    end

    def fact_rule?(index)
      index < facts.length - 1
    end

    def sans
      SANS.html_safe
    end

    def serif
      SERIF.html_safe
    end

    # Single-letter mark for the letterhead, derived from the localized brand
    # string so it never needs its own translation key.
    def monogram
      brand.to_s.strip.first.to_s.upcase
    end

    private

    def coerce_fact(fact)
      return fact if fact.is_a?(Fact)

      data = fact.to_h.symbolize_keys
      Fact.new(
        label: data[:label],
        value: data[:value],
        emphasize: data.fetch(:emphasize, false)
      )
    end
  end
end
