# frozen_string_literal: true

require "rails_helper"
require "stringio"

RSpec.describe CustomDomains::CnameVerifier do
  let(:resolver) { Resolv::DNS.new(nameserver: ["192.0.2.1"], search: ["search.test"], ndots: 5) }
  let(:requester) { instance_double(Resolv::DNS::Requester::ConnectedUDP) }
  let(:sender) { instance_double(Resolv::DNS::Requester::ConnectedUDP::Sender) }
  let(:reply_name) { Resolv::DNS::Name.create("example.test.") }
  let(:reply) { dns_reply }

  def cname(target = "anysys.net.")
    Resolv::DNS::Resource::IN::CNAME.new(Resolv::DNS::Name.create(target))
  end

  # Exercise stdlib message encoding/decoding and fetch_resource's actual
  # retry/cleanup path; only the transport is replaced, never public DNS.
  def dns_reply(answers: [["example.test.", cname]], authority: [], additional: [], rcode: 0, truncated: false)
    message = Resolv::DNS::Message.new
    message.qr = 1
    message.rcode = rcode
    message.tc = truncated ? 1 : 0
    message.add_question("example.test.", Resolv::DNS::Resource::IN::CNAME)
    { answer: answers, authority: authority, additional: additional }.each do |section, records|
      records.each { |owner, resource| message.public_send("add_#{section}", owner, 60, resource) }
    end
    Resolv::DNS::Message.decode(message.encode)
  end

  def verify(hostname: "example.test")
    result = described_class.call(hostname: hostname)
    expect(resolver).to have_received(:close).at_least(:once)
    expect(requester).to have_received(:close).at_least(:once)
    result
  end

  before do
    allow(Resolv::DNS).to receive(:new).and_return(resolver)
    allow(resolver).to receive(:close).and_call_original
    allow(resolver).to receive(:make_udp_requester).and_return(requester)
    allow(requester).to receive(:sender).and_return(sender)
    allow(requester).to receive(:request).and_return([reply, reply_name])
    allow(requester).to receive(:close)
  end

  it "queries the normalized absolute CNAME with finite retry timeouts" do
    expect(resolver).to receive(:timeouts=).with([1]).and_call_original
    expect(resolver).to receive(:fetch_resource).with("example.test.", Resolv::DNS::Resource::IN::CNAME).and_call_original
    expect(requester).to receive(:sender).with(
      an_instance_of(Resolv::DNS::Message), reply_name, "192.0.2.1", 53
    ).and_return(sender)
    expect(requester).to receive(:request).with(sender, 1).and_return([reply, reply_name])
    expect(verify(hostname: "EXAMPLE.TEST.")).to eq(:verified)
  end

  ["anysys.net", "ANYSYS.NET.", "AnYsYs.NeT"].each do |target|
    it "accepts the exact direct target #{target.inspect}" do
      allow(requester).to receive(:request).and_return([
        dns_reply(answers: [["EXAMPLE.TEST.", cname(target)]]), reply_name
      ])
      expect(verify).to eq(:verified)
    end
  end

  it "accepts duplicate direct answers only when their normalized targets agree" do
    allow(requester).to receive(:request).and_return([
      dns_reply(answers: [["example.test", cname], ["EXAMPLE.TEST.", cname("ANYSYS.NET")]]), reply_name
    ])
    expect(verify).to eq(:verified)
  end

  ["other.net", "sub.anysys.net", "anysys.net.evil.test"].each do |target|
    it "rejects the wrong or suffix-matching target #{target.inspect}" do
      allow(requester).to receive(:request).and_return([dns_reply(answers: [["example.test.", cname(target)]]), reply_name])
      expect(verify).to eq(:unverified)
    end
  end

  it "rejects conflicting direct targets" do
    allow(requester).to receive(:request).and_return([
      dns_reply(answers: [["example.test.", cname], ["example.test.", cname("other.net.")]]), reply_name
    ])
    expect(verify).to eq(:unverified)
  end

  it "rejects address-only or flattened aliases even when the address equals the destination" do
    address = Resolv::DNS::Resource::IN::A.new("192.0.2.10")
    ipv6 = Resolv::DNS::Resource::IN::AAAA.new("2001:db8::10")
    allow(requester).to receive(:request).and_return([
      dns_reply(answers: [["example.test.", address], ["example.test.", ipv6], ["anysys.net.", address]]), reply_name
    ])
    expect(verify).to eq(:unverified)
  end

  it "rejects a later CNAME hop to anysys.net" do
    allow(requester).to receive(:request).and_return([
      dns_reply(answers: [["example.test.", cname("hop.test.")], ["hop.test.", cname]]), reply_name
    ])
    expect(verify).to eq(:unverified)
  end

  it "rejects unrelated answer owners" do
    allow(requester).to receive(:request).and_return([dns_reply(answers: [["other.test.", cname]]), reply_name])
    expect(verify).to eq(:unverified)
  end

  it "does not mistake a dot inside an owner or target label for a label separator" do
    dotted_owner = Resolv::DNS::Name.new(["example.test"])
    dotted_target = Resolv::DNS::Name.new(["anysys.net"])
    [
      [[dotted_owner, cname]],
      [["example.test.", Resolv::DNS::Resource::IN::CNAME.new(dotted_target)]]
    ].each do |answers|
      allow(requester).to receive(:request).and_return([dns_reply(answers: answers), reply_name])
      expect(verify).to eq(:unverified)
    end
  end

  it "rejects a reply for a different query name" do
    allow(requester).to receive(:request).and_return([reply, Resolv::DNS::Name.create("other.test.")])
    expect(verify).to eq(:unverified)
  end

  it "ignores CNAMEs in authority and additional sections" do
    allow(requester).to receive(:request).and_return([
      dns_reply(answers: [], authority: [["example.test.", cname]], additional: [["example.test.", cname]]), reply_name
    ])
    expect(verify).to eq(:unverified)
  end

  it "ignores unrelated records when the direct answer is valid" do
    allow(requester).to receive(:request).and_return([
      dns_reply(answers: [["other.test.", cname("other.net")], ["example.test.", cname]],
                additional: [["example.test.", cname("other.net")]]), reply_name
    ])
    expect(verify).to eq(:verified)
  end

  it "rejects empty answers" do
    allow(requester).to receive(:request).and_return([dns_reply(answers: []), reply_name])
    expect(verify).to eq(:unverified)
  end

  [Resolv::DNS::RCode::NXDomain, Resolv::DNS::RCode::ServFail, Resolv::DNS::RCode::Refused].each do |rcode|
    it "fails closed for DNS response code #{rcode}" do
      allow(requester).to receive(:request).and_return([dns_reply(rcode: rcode), reply_name])
      expect(verify).to eq(:unverified)
    end
  end

  [Resolv::ResolvError, Resolv::ResolvTimeout, Resolv::DNS::DecodeError,
   Resolv::DNS::EncodeError, Resolv::DNS::Requester::RequestError,
   SocketError, Errno::ECONNRESET, IOError, EOFError, ArgumentError].each do |error_class|
    it "fails closed and closes resources on #{error_class}" do
      allow(requester).to receive(:request).and_raise(error_class)
      expect(verify).to eq(:unverified)
    end
  end

  it "fails closed on a malformed stdlib-decoded reply" do
    allow(requester).to receive(:request) { Resolv::DNS::Message.decode("broken") }
    expect(verify).to eq(:unverified)
  end

  it "uses one bounded attempt per nameserver without trying search domains" do
    allow(Resolv::DNS).to receive(:new).and_call_original
    multiple = Resolv::DNS.new(nameserver: ["192.0.2.1", "192.0.2.2"], search: ["search.test"], ndots: 5)
    allow(Resolv::DNS).to receive(:new).and_return(multiple)
    allow(multiple).to receive(:make_udp_requester).and_return(requester)
    allow(multiple).to receive(:close).and_call_original
    allow(requester).to receive(:request).with(sender, 1).and_raise(Resolv::ResolvTimeout)

    expect(described_class.call(hostname: "example.test")).to eq(:unverified)
    expect(requester).to have_received(:request).with(sender, 1).twice
    expect(requester).to have_received(:sender).with(anything, reply_name, "192.0.2.1", 53).once
    expect(requester).to have_received(:sender).with(anything, reply_name, "192.0.2.2", 53).once
    expect(multiple).to have_received(:close)
    expect(requester).to have_received(:close)
  end

  context "with TCP fallback" do
    let(:reply) { dns_reply(truncated: true) }
    # fetch_resource uses a TCP class check to avoid repeating fallback.
    let(:tcp) { Resolv::DNS::Requester::TCP.allocate }

    before do
      allow(resolver).to receive(:make_tcp_requester).with("192.0.2.1", 53).and_return(tcp)
      allow(tcp).to receive(:sender).and_return(sender)
      allow(tcp).to receive(:request).and_return([dns_reply, reply_name])
      allow(tcp).to receive(:close)
    end

    it "uses stdlib TCP fallback and closes both requesters" do
      expect(verify).to eq(:verified)
      expect(tcp).to have_received(:request).with(sender, 1)
      expect(tcp).to have_received(:close)
    end

    it "rejects a still-truncated TCP reply" do
      allow(tcp).to receive(:request).and_return([reply, reply_name])
      expect(verify).to eq(:unverified)
      expect(tcp).to have_received(:close)
    end

    it "fails closed on EOF before the TCP length prefix or body" do
      reader = Resolv::DNS::Requester::TCP.allocate
      ["", "\x00\x01"].each do |bytes|
        socket = StringIO.new(bytes)
        reader.instance_variable_set(:@socks, [socket])
        allow(tcp).to receive(:request) { reader.recv_reply([socket]).then { |packet, _| Resolv::DNS::Message.decode(packet) } }
        expect(verify).to eq(:unverified)
      end
      expect(tcp).to have_received(:close).twice
    end

    it "bounds TCP connect with the overall three-second deadline" do
      expect(Timeout).to receive(:timeout).with(3).and_wrap_original do |original, _seconds, &block|
        original.call(0.02, &block)
      end
      allow(resolver).to receive(:make_tcp_requester) { sleep }
      expect(verify).to eq(:unverified)
    end

    it "bounds TCP read with the same deadline and closes the TCP requester" do
      expect(Timeout).to receive(:timeout).with(3).and_wrap_original do |original, _seconds, &block|
        original.call(0.02, &block)
      end
      allow(tcp).to receive(:request) { sleep }
      expect(verify).to eq(:unverified)
      expect(tcp).to have_received(:close)
    end
  end

  it "bounds the complete lookup and closes a waiting UDP requester" do
    expect(Timeout).to receive(:timeout).with(3).and_wrap_original do |original, _seconds, &block|
      original.call(0.02, &block)
    end
    allow(requester).to receive(:request) { sleep }
    expect(verify).to eq(:unverified)
  end

  it "closes the resolver if transport setup fails" do
    allow(resolver).to receive(:make_udp_requester).and_raise(Errno::EMFILE)
    expect(described_class.call(hostname: "example.test")).to eq(:unverified)
    expect(resolver).to have_received(:close)
  end

  it "uses a fresh resolver and checks again instead of caching a successful result" do
    allow(Resolv::DNS).to receive(:new).and_call_original
    second = Resolv::DNS.new(nameserver: ["192.0.2.1"], search: [], ndots: 1)
    allow(Resolv::DNS).to receive(:new).and_return(resolver, second)
    allow(second).to receive(:make_udp_requester).and_return(requester)
    allow(second).to receive(:close).and_call_original
    allow(requester).to receive(:request).and_return([reply, reply_name], [dns_reply(answers: []), reply_name])

    expect(described_class.call(hostname: "example.test")).to eq(:verified)
    expect(described_class.call(hostname: "example.test")).to eq(:unverified)
    expect(resolver).to have_received(:close).once
    expect(second).to have_received(:close).once
    expect(requester).to have_received(:close).twice
  end

  it "rejects invalid hostname input before allocating a resolver" do
    expect(described_class.call(hostname: "https://example.test")).to eq(:unverified)
    expect(Resolv::DNS).not_to have_received(:new)
  end

  it "does not swallow unexpected programming errors" do
    allow(requester).to receive(:request) { nil.unexpected_method }
    expect { described_class.call(hostname: "example.test") }.to raise_error(NoMethodError, /unexpected_method/)
    expect(resolver).to have_received(:close)
    expect(requester).to have_received(:close)
  end
end
