# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sms::RequestAttributes do
  def parse(kind, **fields)
    request = instance_double(ActionDispatch::Request, query_parameters: {}, request_parameters: { "sms_#{kind}" => fields.stringify_keys })
    described_class.new(request: request, kind: kind).call
  end

  it "does not reinterpret invalid, nonobject or duplicate-key JSON as an empty audience" do
    ["{", "[]", "null", '{"name":{},"name":{}}', '{"type":"group","conditions":[{"value":1,"value":2}]}'].each do |json|
      expect { parse(:segment, segment_rules_json: json) }.to raise_error(described_class::Invalid)
    end
    expect(parse(:segment, segment_rules_json: "{}")).to eq(segment_rules: {})
  end

  it "retains the original malformed textarea and other submitted values" do
    expect { parse(:campaign, name: "My draft", variable_map_json: "{broken") }.to raise_error(described_class::Invalid) { |error|
      expect(error.form_values).to eq(name: "My draft", variable_map_json: "{broken")
      expect(error.errors.keys).to eq([:variable_map_json])
    }
  end

  it "rejects protected inputs, nonscalar text and lossy numeric casts" do
    expect { parse(:contact, consent_status: "granted") }.to raise_error(described_class::Invalid)
    expect { parse(:contact, name: ["name"]) }.to raise_error(described_class::Invalid)
    ["1x", "1.0", "-1", " 1", 1.5, true, [1], {}].each do |value|
      expect { parse(:campaign, segment_id: value) }.to raise_error(described_class::Invalid)
    end
    expect(parse(:campaign, segment_id: "", template_id: "17", lock_version: "0")).to eq(segment_id: nil, template_id: 17, lock_version: 0)
  end

  it "converts local schedule to UTC and rejects DST gaps, ambiguities and bad dates" do
    expect(parse(:campaign, scheduled_local: "2026-10-15T10:30", timezone: "Asia/Shanghai")[:scheduled_at]).to eq(Time.utc(2026, 10, 15, 2, 30))
    %w[2026-03-08T02:30 2026-11-01T01:30 2026-02-30T10:00].each do |local|
      expect { parse(:campaign, scheduled_local: local, timezone: "America/New_York") }.to raise_error(described_class::Invalid)
    end
    expect(parse(:campaign, scheduled_local: "")[:scheduled_at]).to be_nil
  end

  it "requires explicit consent offsets and preserves server ownership of the source" do
    expect(parse(:consent_event, occurred_at: "2026-10-12T10:30:00+08:00")[:occurred_at]).to eq(Time.utc(2026, 10, 12, 2, 30))
    expect { parse(:consent_event, occurred_at: "2026-10-12T10:30") }.to raise_error(described_class::Invalid)
    expect { parse(:consent_event, occurred_at: "2026-02-30T12:00:00+08:00") }.to raise_error(described_class::Invalid)
    expect { parse(:consent_event, occurred_at: "2026-10-12T25:30:00+08:00") }.to raise_error(described_class::Invalid)
    expect { parse(:consent_event, source: "provider_opt_out") }.to raise_error(described_class::Invalid)
  end

  it "bounds JSON fields and request streams, even with no Content-Length" do
    expect { parse(:campaign, variable_map_json: JSON.generate("value" => "x" * (16 * 1024))) }.to raise_error(described_class::Invalid)
    body = StringIO.new("x" * (described_class::MAX_BYTES + 1))
    request = instance_double(ActionDispatch::Request, content_length: nil, body: body, media_type: "application/x-www-form-urlencoded")
    expect { described_class.check_body!(request) }.to raise_error(described_class::Invalid)
    expect(body.pos).to eq(0)
  end
end
