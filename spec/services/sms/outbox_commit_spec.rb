# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SMS transactional outbox", type: :job do
  self.use_transactional_tests = false

  before do
    @customer = create(:customer)
    @sms_module_created = !FeatureModules::Module.exists?(key: "sms")
    @sms_module = enable_module!("sms", @customer, name: "SMS")
    @credential = create(:sms_credential)
    @template = create(:sms_template, variables: [])
    clear_enqueued_jobs
  end

  after do
    # Remove only these committed fixtures; preserve existing DB rows and seeds.
    Sms::Message.where(customer_id: @customer.id).delete_all if @customer
    @template&.destroy!
    @credential&.destroy!
    @customer&.destroy!
    @sms_module&.destroy! if @sms_module_created
    clear_enqueued_jobs
    Current.reset
  end

  def admit(**options)
    Sms::Activities::Send.call(**{ customer: @customer, to: "+8613800138000", template_key: @template.key, vars: {} }.merge(options))
  end

  it "enqueues only after the outermost transaction commits, never from an inner savepoint" do
    message = nil
    expect(Sms::DeliverMessageJob).to receive(:perform_later).once.and_wrap_original do |method, id|
      expect(ApplicationRecord.connection.open_transactions).to eq(0)
      expect(Sms::Message.find(id).status).to eq("queued")
      method.call(id)
    end

    ApplicationRecord.transaction do
      ApplicationRecord.transaction(requires_new: true) { message = admit }
      expect(enqueued_jobs).to be_empty
      expect(message.delivery_enqueued_at).to be_nil
    end
    expect(enqueued_jobs.map { |job| job[:args] }).to eq([[message.id]])
    expect(message.reload.delivery_enqueued_at).to be_present
  end

  it "discards the admission and accelerator on outer transaction rollback" do
    message = nil
    ApplicationRecord.transaction do
      message = admit
      raise ActiveRecord::Rollback
    end
    expect(Sms::Message.exists?(id: message.id)).to be(false)
    expect(enqueued_jobs).to be_empty
  end

  it "recovers an enqueue failure from the committed outbox without another admission or payload reservation" do
    allow(Sms::DeliverMessageJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "unavailable")
    message = admit(idempotency_key: "outbox")
    expect(message.reload.status).to eq("queued")
    expect(message.delivery_enqueued_at).to be_nil
    allow(Sms::DeliverMessageJob).to receive(:perform_later).and_call_original
    expect { Sms::Cron::RecoverMessages.call }.to have_enqueued_job(Sms::DeliverMessageJob).with(message.id)
    expect(admit(idempotency_key: "outbox").id).to eq(message.id)
    expect(Sms::Message.where(customer_id: @customer.id).count).to eq(1)
  end

  it "recovers a stamped enqueue whose queue execution was lost and limits repeated accelerators" do
    message = admit
    clear_enqueued_jobs
    expect { Sms::Cron::RecoverMessages.call }.not_to have_enqueued_job(Sms::DeliverMessageJob)
    message.update_columns(delivery_enqueued_at: 10.minutes.ago)
    expect { Sms::Cron::RecoverMessages.call }.to have_enqueued_job(Sms::DeliverMessageJob).with(message.id)
    clear_enqueued_jobs
    expect { Sms::Cron::RecoverMessages.call }.not_to have_enqueued_job(Sms::DeliverMessageJob)
    expect(message.reload.delivery_attempts).to eq(0)
  end

  it "preserves committed acceptance if the accelerator stamp and cleanup both fail" do
    message = nil
    expect {
      ApplicationRecord.transaction do
        message = admit
        scope = double("unavailable accelerator scope")
        allow(scope).to receive(:where).and_return(scope)
        allow(scope).to receive(:update_all).and_raise(ActiveRecord::StatementInvalid, "temporary DB interruption")
        allow(Sms::Message).to receive(:where).and_call_original
        allow(Sms::Message).to receive(:where)
          .with(hash_including(id: message.id, status: "queued", dispatch_started_at: nil)).and_return(scope)
      end
    }.not_to raise_error
    expect(message.reload.status).to eq("queued")
    expect(message.delivery_enqueued_at).to be_nil
  end

  it "persists the attempted marker in a committed transaction before the vendor sees the payload" do
    message = admit
    expect_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message) do
      expect(ApplicationRecord.connection.open_transactions).to eq(0)
      durable = Thread.new do
        ApplicationRecord.connection_pool.with_connection { Sms::Message.find(message.id).dispatch_started_at }
      end.value
      expect(durable).to be_present
      { vendor_message_id: "committed-id", raw: {} }
    end
    Sms::DeliverMessageJob.new.perform(message.id)
    expect(message.reload.status).to eq("sent")
    expect(message.delivery_attempts).to eq(1)
  end

  it "defers recovery's accelerator until an enclosing transaction commits too" do
    message = admit
    clear_enqueued_jobs
    message.update_columns(delivery_enqueued_at: nil)
    ApplicationRecord.transaction do
      Sms::Cron::RecoverMessages.call
      expect(enqueued_jobs).to be_empty
    end
    expect(enqueued_jobs.map { |job| job[:args] }).to eq([[message.id]])
  end

  it "makes only one external call when distinct workers race on the committed ledger" do
    message = admit
    entered = Queue.new
    finish = Queue.new
    calls = []
    allow_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message) do
      calls << message.id
      entered << true
      finish.pop
      { vendor_message_id: "one-id", raw: {} }
    end
    first = Thread.new do
      ApplicationRecord.connection_pool.with_connection { Sms::DeliverMessageJob.new.perform(message.id) }
    end
    entered.pop
    second = Thread.new do
      ApplicationRecord.connection_pool.with_connection { Sms::DeliverMessageJob.new.perform(message.id) }
    end
    second.value
    finish << true
    first.value
    expect(calls).to eq([message.id])
    expect(message.reload.delivery_attempts).to eq(1)
  ensure
    finish << true if finish
    first&.join
    second&.join
  end
end
