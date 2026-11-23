# frozen_string_literal: true
require "rails_helper"
require_relative "../../services/billing/partition_b_helpers"

RSpec.describe Billing::DispatchNoticeJob do
  include BillingPartitionBHelpers

  it "leaves the outbox pending after transport failure and dispatches the same event on retry" do
    aggregate = billing_aggregate
    notice = Billing::Notice.find_by!(event_key: "invoice_issued:#{aggregate.fetch(:invoice).id}")
    delivery = instance_double(ActionMailer::MessageDelivery)
    allow(BillingMailer).to receive(:notice).with(notice).and_return(delivery)
    allow(delivery).to receive(:deliver_now).and_raise(IOError, "mail transport")
    expect { described_class.new.perform(notice.id) }.to raise_error(IOError)
    expect(notice.reload.state).to eq("pending")
    allow(delivery).to receive(:deliver_now)
    2.times { described_class.new.perform(notice.id) }
    expect(notice.reload.state).to eq("enqueued")
    expect(delivery).to have_received(:deliver_now).twice
  end
end
