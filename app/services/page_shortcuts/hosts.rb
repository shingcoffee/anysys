# frozen_string_literal: true

require "addressable/uri"

module PageShortcuts
  module Hosts
    module_function

    def normalize(host)
      return unless host.is_a?(String) && host.valid_encoding? && host.present?

      uri = Addressable::URI.parse("http://#{host}")
      return if uri.userinfo || uri.port || uri.query || uri.fragment || uri.path.present?
      return unless uri.authority == host && !host.include?("%")

      hostname = uri.normalized_host.to_s.delete_suffix(".")
      return unless hostname.bytesize <= 253 && hostname.split(".", -1).all? do |label|
        label.match?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/)
      end

      hostname
    rescue Addressable::URI::InvalidURIError, ArgumentError
      nil
    end

    def customer_id(host = nil)
      hostname = normalize(host)
      cid = Customer.domain_owner_id(hostname) if hostname
      cid || Rails.application.config.x.page_shortcuts.default_customer_id
    end

    def dedicated?(host)
      hostname = normalize(host)
      return false unless hostname

      Customer.domain_owner_id(hostname).present?
    end

    def prefix(customer_id:, host: nil)
      cid = PathPolicy.customer_id(customer_id)
      return unless cid

      self.customer_id(host) == cid ? "" : "/#{cid}"
    end

    def path(path, customer_id:, host: nil)
      prefix = prefix(customer_id: customer_id, host: host)
      "#{prefix}#{path}" if prefix
    end
  end
end
