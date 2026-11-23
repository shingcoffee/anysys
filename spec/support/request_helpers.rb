# frozen_string_literal: true

# JSON / Bearer header builders for request specs.
module RequestHelpers
  def json_headers(extra = {})
    { "ACCEPT" => "application/json", "CONTENT_TYPE" => "application/json" }.merge(extra)
  end

  def bearer_headers(token, extra = {})
    { "Authorization" => "Bearer #{token}", "ACCEPT" => "application/json" }.merge(extra)
  end
end

RSpec.configure do |config|
  config.include RequestHelpers, type: :request
end
