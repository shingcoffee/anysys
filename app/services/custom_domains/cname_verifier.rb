# frozen_string_literal: true

require "resolv"
require "timeout"

module CustomDomains
  class CnameVerifier
    def self.call(hostname:)
      candidate = PageShortcuts::Hosts.normalize(hostname)
      return :unverified unless candidate

      outcome = :unverified
      # Resolv bounds each attempt; the outer deadline also bounds multiple
      # nameservers and TCP fallback/connect/read. Keep it local to DNS I/O.
      Timeout.timeout(3) do
        Resolv::DNS.open do |resolver|
          resolver.timeouts = [1]
          query = Resolv::DNS::Name.create("#{candidate}.")
          resolver.fetch_resource("#{candidate}.", Resolv::DNS::Resource::IN::CNAME) do |reply, reply_name|
            outcome = :verified if direct_answer?(reply, reply_name, query)
          end
        end
      end
      outcome
    rescue Resolv::ResolvError, Resolv::ResolvTimeout, Resolv::DNS::DecodeError,
           Resolv::DNS::EncodeError, Resolv::DNS::Requester::RequestError,
           Timeout::Error, SocketError, SystemCallError, IOError, ArgumentError
      :unverified
    rescue NoMethodError => error
      # Ruby 3.2 Resolv's TCP reader calls unpack/bytesize on nil when a peer
      # closes before the length prefix/body. Do not hide unrelated code errors.
      raise unless error.receiver.nil? && %i[unpack bytesize].include?(error.name)

      :unverified
    end

    def self.direct_answer?(reply, reply_name, query)
      return false unless reply.rcode == Resolv::DNS::RCode::NoError && reply.tc == 0
      return false unless reply_name.to_a == query.to_a

      targets = []
      # getresources/extract_resources lose owner identity, follow aliases and
      # include other sections. Only direct answer-section owners count here.
      reply.each_answer do |owner, _ttl, resource|
        next unless owner.to_a == query.to_a && resource.is_a?(Resolv::DNS::Resource::IN::CNAME)

        # Compare DNS labels, not joined strings (a label can contain a dot).
        targets << resource.name.to_a
      end
      targets.uniq == [Resolv::DNS::Name.create("anysys.net.").to_a]
    end
    private_class_method :direct_answer?
  end
end
