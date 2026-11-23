# frozen_string_literal: true

module Member
  # Single module mapping descriptor format keys to rendered strings.
  # The kit calls Member::Formatters.format(value, key); descriptors
  # never write Tailwind classes for known data shapes.
  module Formatters
    extend ActionView::Helpers::OutputSafetyHelper

    STATUS_TONES = {
      "succeeded" => :success, "active"  => :success, "paid"     => :success,
      "failed"    => :danger,  "refused" => :danger,  "cancelled" => :danger,
      "pending"   => :warning, "processing" => :warning,
      "created"   => :default, "closed"  => :default
    }.freeze

    KNOWN = %i[string date datetime money money_large money_major money_major_large number number_large status_pill mono].freeze

    def self.format(value, key)
      return "" if value.nil?

      case key
      when :string        then ERB::Util.html_escape(value.to_s)
      when :date          then I18n.l(value, format: :long)
      when :datetime      then I18n.l(value, format: :long)
      when :money         then format_cents(value)
      when :money_large
        raw(%(<span class="text-3xl font-semibold font-mono">#{ERB::Util.html_escape(format_cents(value))}</span>))
      when :money_major    then format_major(value)
      when :money_major_large
        raw(%(<span class="text-3xl font-semibold font-mono">#{ERB::Util.html_escape(format_major(value))}</span>))
      when :number        then value.to_s
      when :number_large
        raw(%(<span class="text-3xl font-semibold">#{ERB::Util.html_escape(value.to_s)}</span>))
      when :status_pill
        key = value.to_s
        label = if STATUS_TONES.key?(key)
          I18n.t("common.status.#{key}")
        else
          key
        end
        tone = STATUS_TONES.fetch(key, :default)
        raw(%(<span class="badge badge-#{tone}">#{ERB::Util.html_escape(label)}</span>))
      when :mono
        raw(%(<span class="font-mono break-all">#{ERB::Util.html_escape(value.to_s)}</span>))
      else
        raise ArgumentError, "unknown format key: #{key.inspect} (known: #{KNOWN.inspect})"
      end
    end

    def self.format_major(value)
      amount, currency = money_parts(value)
      return "" if amount.nil?

      Billing::CurrencyResolver.format_amount(amount, currency.presence || "USD")
    end
    private_class_method :format_major

    def self.format_cents(value)
      cents, currency = money_parts(value)
      return "" if cents.nil?

      Billing::CurrencyResolver.format(cents, currency.presence || "USD")
    end
    private_class_method :format_cents

    def self.money_parts(value)
      case value
      when Hash
        [value[:amount] || value["amount"], value[:currency] || value["currency"]]
      else
        [value, nil]
      end
    end
    private_class_method :money_parts
  end
end
