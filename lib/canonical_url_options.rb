# frozen_string_literal: true

require "uri"
require "ipaddr"

# Shared validation for the already-parsed environment URL options. This runs
# without loading models during boot and is reused by request-independent links.
module CanonicalUrlOptions
  module_function

  def assets_only_build?(env: ENV, tasks: nil)
    tasks ||= defined?(Rake) && Rake.respond_to?(:application) ? Rake.application.top_level_tasks : ARGV
    !env["SECRET_KEY_BASE_DUMMY"].to_s.empty? && !tasks.empty? && tasks.all? { |task| task == "assets:precompile" }
  end

  def validate(options, production:)
    options = options.to_h.transform_keys(&:to_sym)
    host = options[:host].to_s
    protocol = options.fetch(:protocol, production ? "https" : "http").to_s.downcase
    unless !host.empty? && %w[http https].include?(protocol) && (!production || protocol == "https")
      raise ArgumentError, "canonical URL requires a host and an appropriate HTTP(S) protocol"
    end

    uri = URI.parse("#{protocol}://#{host}")
    unless uri.host == host && uri.userinfo.nil? && uri.path.empty? && uri.query.nil? && uri.fragment.nil?
      raise ArgumentError, "APP_HOST must contain only a hostname or IP address; configure its port separately"
    end
    if production && local_host?(uri.hostname)
      raise ArgumentError, "production canonical URL cannot use a loopback or wildcard host"
    end

    port = options[:port].nil? ? nil : Integer(options[:port])
    raise ArgumentError, "APP_PORT must be between 1 and 65535" if port && !port.between?(1, 65_535)

    options.merge(host: host, protocol: protocol, port: port)
  rescue URI::InvalidURIError, TypeError
    raise ArgumentError, "invalid canonical URL configuration"
  end

  def local_host?(host)
    name = host.downcase.delete_suffix(".")
    return true if name == "localhost" || name.end_with?(".localhost")

    address = IPAddr.new(host)
    address.loopback? || address.to_i.zero?
  rescue IPAddr::InvalidAddressError
    false
  end
  private_class_method :local_host?
end
