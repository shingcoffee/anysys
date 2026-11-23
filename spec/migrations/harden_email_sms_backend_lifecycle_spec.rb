# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261011173041_harden_email_sms_backend_lifecycle")

RSpec.describe HardenEmailSmsBackendLifecycle do
  let(:migration) { described_class.new }

  it "permits the preflight for a fresh outbox with no historical queued rows" do
    expect { migration.send(:reject_unresolved_email_outbox!) }.not_to raise_error
  end

  it "refuses unresolved queued rows before any schema mutation and preserves their records" do
    message = create(:email_message, :queued, delivery_due_at: nil)
    expect(migration).not_to receive(:change_table)

    expect {
      migration.suppress_messages { migration.migrate(:up) }
    }.to raise_error(ActiveRecord::MigrationError, /Resolve or quarantine queued email messages/)

    expect(message.reload.status).to eq("queued")
    expect(message.delivery_due_at).to be_nil
  end

  it "does not classify already completed mail as an unresolved delivery schedule" do
    create(:email_message, :sent, delivery_due_at: nil)
    create(:email_message, :failed, delivery_due_at: nil)

    expect { migration.send(:reject_unresolved_email_outbox!) }.not_to raise_error
  end
end
