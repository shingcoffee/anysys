# frozen_string_literal: true

module Payments
  # Terminal page rendered after the payment resolves — renders a success view
  # on `succeeded`, otherwise shows the current status. The controller resolves
  # the "Return" destination (honoring the handoff exit_target) and injects it,
  # so this component stays free of session / exit-resolution concerns.
  class ResultComponent < ApplicationComponent
    def initialize(payment:, return_path:)
      @payment     = payment
      @return_path = return_path
    end

    attr_reader :payment, :return_path

    def success?
      payment.status == "succeeded"
    end

    def pending?
      payment.status.in?(%w[pending created])
    end

    def status_label
      key = payment.status.to_s
      if Payments::Payment::STATUSES.include?(key)
        I18n.t("comp_payments.result.statuses.#{key}")
      else
        key
      end
    end
  end
end
