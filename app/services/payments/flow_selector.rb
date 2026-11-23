# frozen_string_literal: true

module Payments
  # Picks the right checkout flow (jsapi / h5 / qr / card) for an incoming request.
  # Intersects the request UA heuristic with the gateway's declared supported_flows.
  # Card processors (Stripe) declare only [:card], which short-circuits UA branching.
  # China gateways (Alipay, WeChat Pay) declare [:qr, :h5, :jsapi] and use the
  # existing vendor-specific in-app UA detection.
  class FlowSelector
    MOBILE_UA = /Mobile|Android|iPhone|iPad/i

    def self.call(request:, provider:)
      gateway  = Payments::Gateways.for(provider)
      supported = gateway.supported_flows

      # Card processors expose only :card — no UA branching needed.
      return :card if supported == %i[card]

      ua      = request.user_agent.to_s
      pattern = gateway.respond_to?(:jsapi_user_agent_pattern) ? gateway.jsapi_user_agent_pattern : nil
      return :jsapi if pattern && ua.match?(pattern) && supported.include?(:jsapi)
      return :h5    if ua.match?(MOBILE_UA) && supported.include?(:h5)
      supported.include?(:qr) ? :qr : supported.first
    end
  end
end
