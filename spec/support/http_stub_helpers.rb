# frozen_string_literal: true

# Thin WebMock wrapper for JSON APIs. WebMock itself is loaded in webmock.rb.
module HttpStubHelpers
  def stub_json(method, url, status: 200, body: {}, headers: {})
    payload = body.is_a?(String) ? body : body.to_json
    stub_request(method, url).to_return(
      status: status,
      body: payload,
      headers: { "Content-Type" => "application/json" }.merge(headers)
    )
  end
end

RSpec.configure do |config|
  config.include HttpStubHelpers
end
