# frozen_string_literal: true

# Flowchart HTTP goes through OutboundHttp with public_only: true, which
# resolves the host before connecting. WebMock stubs Net::HTTP, not DNS, so
# specs that hit example.com / api.example.com would otherwise call Resolv.
# Default: every host resolves to a public address. Opt out with
# :real_dns_guard when the example needs to exercise the SSRF classifier.
RSpec.configure do |config|
  config.before do |example|
    next if example.metadata[:real_dns_guard]

    allow(OutboundHttp::PublicAddress).to receive(:resolve).and_return(["93.184.216.34"])
  end
end
