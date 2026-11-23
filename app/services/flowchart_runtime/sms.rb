# frozen_string_literal: true

module FlowchartRuntime
  # Workflow sends use the same tenant ledger, approved templates, credentials,
  # suppression, quotas and asynchronous dispatch as every other SMS caller.
  module Sms
    module_function

    def send_template(customer:, to:, template_key:, vars: {}, idempotency_key: nil, expires_at: nil)
      ::Sms::Gateway.send(
        customer: customer, to: to, template_key: template_key, vars: vars,
        idempotency_key: idempotency_key, expires_at: expires_at
      )
    end
  end
end
