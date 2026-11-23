# frozen_string_literal: true

require "ipaddr"
require "resolv"

class OutboundHttp
  # Pure classifier used by the public_only SSRF guard. An address is public
  # only when every check below passes; IPv4-mapped IPv6 is classified by the
  # embedded IPv4.
  module PublicAddress
    BLOCKED_RANGES = [
      IPAddr.new("0.0.0.0/8"),
      IPAddr.new("100.64.0.0/10"),
      IPAddr.new("192.0.0.0/24"),
      IPAddr.new("198.18.0.0/15"),
      IPAddr.new("224.0.0.0/4"),
      IPAddr.new("240.0.0.0/4"),
      IPAddr.new("::/96"),
      IPAddr.new("64:ff9b::/96"),
      IPAddr.new("fc00::/7"),
      IPAddr.new("ff00::/8")
    ].freeze

    class << self
      def public?(ip_string)
        ip = parse(ip_string)
        return false unless ip
        return public_unicast?(ip.native) if ip.ipv4_mapped?

        public_unicast?(ip)
      end

      def resolve(host)
        Resolv.getaddresses(strip_brackets(host))
      end

      private

      def public_unicast?(ip)
        return false if ip.loopback? || ip.private? || ip.link_local?
        return false if ip.to_s == "255.255.255.255"

        BLOCKED_RANGES.none? { |range| range.include?(ip) }
      end

      def parse(ip_string)
        IPAddr.new(strip_brackets(ip_string))
      rescue IPAddr::Error
        nil
      end

      def strip_brackets(value)
        value.to_s.sub(/\A\[/, "").sub(/\]\z/, "")
      end
    end
  end
end
