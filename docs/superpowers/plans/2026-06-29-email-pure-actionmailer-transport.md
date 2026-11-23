# Email & Email Campaign — Pure ActionMailer Transport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make both the Email module and the Email Campaign module send mail purely through ActionMailer (a `Mailer` action + `deliver_later` + `register_interceptor`/`register_observer`), retiring the hand-rolled `Mail.new` transport — while preserving every non-transport behavior (ledger, idempotency, daily cap, per-mode DB credentials, DKIM, campaign fan-out, customer-editable Lexxy templates). Separately, clean up the dead Trix **editor** assets that Lexxy replaced.

**Architecture:** Introduce `Emails::DeliveryMailer` with one action `deliver_email` that reads an already-rendered `Emails::Message` ledger row and emits multipart text+html via `mail(...)`, passing per-mode DB SMTP credentials natively through `delivery_method_options:`. An `Emails::DkimInterceptor` signs via the existing `Email::DkimSigner` before transport; an `Emails::DeliveryObserver` flips the ledger row to `sent` after success; both are scoped by `X-Anysys-*` correlation headers so they no-op on all other app mail. `Email::Gateway`/`Email::Activities::Send` change only their enqueue line. `Email::Adapters::Smtp` and `Email::DeliveryJob` are deleted.

**Tech Stack:** Rails 8.1 ActionMailer, ActiveJob (`deliver_later` → framework `ActionMailer::MailDeliveryJob`), the `dkim` gem (via `Email::DkimSigner`), Active Storage (inline blobs), RSpec, Lexxy (Action Text editor).

---

## File Structure

**Create:**
- `app/mailers/emails/delivery_mailer.rb` — single `deliver_email` action; builds the envelope + multipart body from the ledger row, native SMTP options, correlation headers, tenant-scoped inline blobs, failure bookkeeping.
- `app/mailers/emails/dkim_interceptor.rb` — `delivering_email` hook; resolves per-mode credential, delegates to `Email::DkimSigner`.
- `app/mailers/emails/delivery_observer.rb` — `delivered_email` hook; `mark_sent!`.
- `config/initializers/email_delivery.rb` — registers interceptor + observer; configures transient-error retry on `ActionMailer::MailDeliveryJob`.
- `spec/mailers/emails/delivery_mailer_spec.rb`
- `spec/mailers/emails/dkim_interceptor_spec.rb`
- `spec/mailers/emails/delivery_observer_spec.rb`

**Modify:**
- `app/services/email/gateway.rb` — 3 enqueue sites switch from `DeliveryJob.perform_later` to `DeliveryMailer...deliver_later`.
- `app/services/email/activities/send.rb` — 1 enqueue site (step 7).
- `app/assets/stylesheets/actiontext.css` — strip Trix **editor** chrome rules; keep `.trix-content` display rules.
- `app/javascript/controllers/template_editor_mode_controller.js` — drop "Trix" comments/naming.
- `app/controllers/admin/modules/emails/attachments_controller.rb` — comment wording.

**Delete:**
- `app/services/email/adapters/smtp.rb`
- `app/jobs/email/delivery_job.rb`
- `spec/services/email/adapters/smtp_spec.rb`
- `spec/jobs/email/delivery_job_spec.rb`

**Unchanged (must NOT be touched):** `Emails::Message`, `Emails::Template`, `Email::CredentialResolver`, `Email::DkimSigner`, `Email::VariableContext`, `Email::TemplateRenderer`, `Emails::CompileTemplate`, `EmailCampaigns::*`, the Lexxy editor + `template_variable_picker_controller.js`, `app/views/layouts/action_text/contents/_content.html.erb`.

---

## Task 1: `Emails::DeliveryMailer`

**Files:**
- Create: `app/mailers/emails/delivery_mailer.rb`
- Test: `spec/mailers/emails/delivery_mailer_spec.rb`

Notes for the implementer:
- The ledger row (`Emails::Message`) is **already rendered** upstream by `Email::TemplateRenderer` — `subject`, `body_html`, `body_text`, `to`, `from`, `cc`, `bcc`, `reply_to` are all populated. The mailer does **no** rendering of template content; it emits the stored strings.
- Render with `layout false` and `render plain:`/`render html:` so the stored `body_html` becomes the html part verbatim — this matches the retired `Email::Adapters::Smtp` exactly (it set `html_part body msg.body_html` with no layout).
- SMTP credentials come from the DB per mode and are passed natively via `delivery_method_options:` on the `mail(...)` call (the documented per-message override) — never from static `config.action_mailer.smtp_settings`.
- Correlation headers `X-Anysys-Message-Id` and `X-Anysys-Mode` let the interceptor/observer act without DB-guessing and keep them scoped to this module's mail only.
- Inline-blob logic is moved verbatim from the retired adapter: only blobs owned by `message.customer_id` (via `ActiveStorage::Blob.for_customer`) are inlined, so a tampered metadata blob id cannot pull another tenant's file into outgoing mail.
- Failure bookkeeping: `rescue_from StandardError` marks the ledger row `failed` (mapping the error class to `failure_code`) and re-raises so ActiveJob retry still applies. ActionMailer runs `rescue_from` handlers around delivery (`deliver_now` wraps `message.deliver` in `handle_exceptions`), so transport errors raised at send time are caught here.

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/mailers/emails/delivery_mailer_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::DeliveryMailer, type: :mailer do
  let(:customer)    { create(:customer) }
  let!(:credential) { create(:email_credential, mode: "sandbox", host: "smtp.test", username: "smtp@example.com") }
  let(:message) do
    create(:email_message, :queued, customer: customer,
      to: "r@example.com", from: "s@example.com", cc: "c@example.com",
      subject: "Hello {{name}}", body_html: "<p>Hi body</p>", body_text: "Hi text")
  end

  def build = described_class.with(message_id: message.id, mode: "sandbox").deliver_email

  it "pulls the envelope from the ledger row" do
    m = build
    expect(m.to).to eq(["r@example.com"])
    expect(m.from).to eq(["s@example.com"])
    expect(m.cc).to eq(["c@example.com"])
    expect(m.subject).to eq("Hello {{name}}") # already-rendered; mailer does not interpolate
  end

  it "emits the stored body as multipart text + html (no layout wrapping)" do
    m = build
    expect(m.text_part.body.decoded).to include("Hi text")
    expect(m.html_part.body.decoded).to include("<p>Hi body</p>")
    expect(m.html_part.body.decoded).not_to include("<html") # layout false
  end

  it "stamps correlation headers and native SMTP options" do
    m = build
    expect(m["X-Anysys-Message-Id"].value).to eq(message.id.to_s)
    expect(m["X-Anysys-Mode"].value).to eq("sandbox")
    expect(m.delivery_method.settings[:address]).to eq("smtp.test")
    expect(m.delivery_method.settings[:user_name]).to eq("smtp@example.com")
  end

  it "no-ops (delivers nothing) when the ledger row is missing" do
    expect { described_class.with(message_id: -1, mode: "sandbox").deliver_email.deliver_now }
      .not_to change { ActionMailer::Base.deliveries.size }
  end

  it "inlines only same-tenant blobs" do
    own = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("a"), filename: "a.png", content_type: "image/png")
    own.update!(customer_id: customer.id)
    other = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("b"), filename: "b.png", content_type: "image/png")
    other.update!(customer_id: create(:customer).id)
    message.update!(metadata: { "attachment_blob_ids" => [own.id, other.id] })

    cids = build.attachments.select(&:inline?).map { |p| p.content_id.to_s }
    expect(cids.join).to include("blob-#{own.id}")
    expect(cids.join).not_to include("blob-#{other.id}")
  end

  it "marks the ledger row failed and re-raises when transport fails" do
    allow_any_instance_of(described_class).to receive(:smtp_settings).and_return(address: "smtp.test", port: 587)
    mailer = described_class.with(message_id: message.id, mode: "sandbox").deliver_email
    allow(mailer.message).to receive(:deliver).and_raise(Net::SMTPServerBusy.new("busy"))
    expect { mailer.deliver_now }.to raise_error(Net::SMTPServerBusy)
    expect(message.reload.status).to eq("failed")
    expect(message.failure_code).to eq("Net::SMTPServerBusy")
  end
end
```

- [ ] **Step 2: Run the spec, verify it fails**

Run: `bundle exec rspec spec/mailers/emails/delivery_mailer_spec.rb`
Expected: FAIL — `uninitialized constant Emails::DeliveryMailer`.

- [ ] **Step 3: Implement the mailer**

```ruby
# app/mailers/emails/delivery_mailer.rb
# frozen_string_literal: true

module Emails
  # Pure-ActionMailer transport for the Email + Email Campaign modules.
  #
  # The Emails::Message ledger row is ALREADY rendered upstream
  # (Email::TemplateRenderer): subject/body_html/body_text/envelope are stored.
  # This mailer does NO content rendering — it emits the stored strings verbatim
  # (layout false, so body_html is the html part as-is, matching the retired
  # Email::Adapters::Smtp). Per-mode DB SMTP credentials are passed natively via
  # delivery_method_options:. X-Anysys-* headers scope the interceptor/observer
  # to this module's mail only.
  class DeliveryMailer < ApplicationMailer
    layout false

    rescue_from StandardError do |error|
      @message&.mark_failed!(code: error.class.name, message: error.message)
      raise error
    end

    # message_id + mode arrive via `.with(...)`.
    def deliver_email
      @message = Emails::Message.find_by(id: params[:message_id])
      return if @message.nil?

      mode       = params[:mode] || Email::CredentialResolver.default_mode
      credential = Email::CredentialResolver.call(mode: mode)

      attach_inline_blobs(@message)

      headers["X-Anysys-Message-Id"] = @message.id.to_s
      headers["X-Anysys-Mode"]       = mode

      message_record = @message
      mail(
        to:                      message_record.to,
        from:                    message_record.from,
        cc:                      message_record.cc.presence,
        bcc:                     message_record.bcc.presence,
        reply_to:                message_record.reply_to.presence,
        subject:                 message_record.subject,
        delivery_method_options: smtp_settings(credential)
      ) do |format|
        format.text { render plain: message_record.body_text.to_s }
        format.html { render html: message_record.body_html.to_s.html_safe }
      end
    end

    private

    def attach_inline_blobs(message)
      (message.metadata&.dig("attachment_blob_ids") || []).each do |id|
        blob = ActiveStorage::Blob.for_customer(message.customer_id).find_by(id: id)
        next unless blob

        name = "blob-#{id}"
        attachments.inline[name] = blob.download
        attachments[name].content_id = "<blob-#{id}>"
      end
    end

    def smtp_settings(credential)
      {
        address:              credential.host,
        port:                 credential.port,
        user_name:            credential.username,
        password:             credential.password,
        authentication:       credential.authentication.to_sym,
        enable_starttls_auto: credential.enable_starttls,
        ssl:                  credential.ssl,
        domain:               credential.domain
      }.compact
    end
  end
end
```

- [ ] **Step 4: Run the spec, verify it passes**

Run: `bundle exec rspec spec/mailers/emails/delivery_mailer_spec.rb`
Expected: PASS (all examples).

- [ ] **Step 5: Commit**

```bash
git add app/mailers/emails/delivery_mailer.rb spec/mailers/emails/delivery_mailer_spec.rb
git commit -m "feat(email): pure-ActionMailer DeliveryMailer for ledger-row transport

Co-Authored-By: Copilot Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `Emails::DkimInterceptor`

**Files:**
- Create: `app/mailers/emails/dkim_interceptor.rb`
- Test: `spec/mailers/emails/dkim_interceptor_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/mailers/emails/dkim_interceptor_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::DkimInterceptor do
  def mail_for(mode:)
    Mail.new do
      to "a@b.com"
      from "s@example.com"
      subject "Hi"
      body "x"
    end.tap { |m| m["X-Anysys-Mode"] = mode }
  end

  context "when the mode's credential has DKIM configured" do
    let!(:credential) do
      create(:email_credential, mode: "sandbox",
        dkim_enabled: true, dkim_domain: "example.com",
        dkim_selector: "mail", dkim_private_key: OpenSSL::PKey::RSA.new(2048).to_pem)
    end

    it "adds a DKIM-Signature header" do
      mail = mail_for(mode: "sandbox")
      described_class.delivering_email(mail)
      expect(mail.header["DKIM-Signature"]).to be_present
      expect(mail.header["DKIM-Signature"].value).to include("d=example.com")
    end

    it "strips the X-Anysys-Mode header after signing" do
      mail = mail_for(mode: "sandbox")
      described_class.delivering_email(mail)
      expect(mail["X-Anysys-Mode"]).to be_nil
    end
  end

  context "when the mode's credential has no DKIM configured" do
    let!(:credential) { create(:email_credential, mode: "sandbox") }

    it "does not add a DKIM-Signature header but still strips the mode header" do
      mail = mail_for(mode: "sandbox")
      described_class.delivering_email(mail)
      expect(mail.header["DKIM-Signature"]).to be_nil
      expect(mail["X-Anysys-Mode"]).to be_nil
    end
  end

  context "when no active credential exists for the mode" do
    it "does not raise, leaves the mail unsigned, and strips the mode header" do
      allow(Email::CredentialResolver).to receive(:call).and_raise(Email::Errors::CredentialsMissing)
      mail = mail_for(mode: "sandbox")
      expect { described_class.delivering_email(mail) }.not_to raise_error
      expect(mail.header["DKIM-Signature"]).to be_nil
      expect(mail["X-Anysys-Mode"]).to be_nil
    end
  end

  context "when no mode header is present (foreign mail)" do
    it "is a no-op and does not raise" do
      mail = Mail.new { to "a@b.com"; from "s@x.com"; subject "Hi"; body "x" }
      expect { described_class.delivering_email(mail) }.not_to raise_error
      expect(mail.header["DKIM-Signature"]).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run the spec, verify it fails**

Run: `bundle exec rspec spec/mailers/emails/dkim_interceptor_spec.rb`
Expected: FAIL — `uninitialized constant Emails::DkimInterceptor`.

- [ ] **Step 3: Implement the interceptor**

```ruby
# app/mailers/emails/dkim_interceptor.rb
# frozen_string_literal: true

module Emails
  # ActionMailer delivery interceptor: signs outgoing Email-module mail with
  # DKIM before it hits the transport. Scoped by the X-Anysys-Mode header so it
  # never touches BillingMailer / Devise / other app mail. Signing itself stays
  # in Email::DkimSigner (the `dkim`-gem wrapper); this only resolves the right
  # per-mode credential and invokes it.
  class DkimInterceptor
    def self.delivering_email(mail)
      mode = mail["X-Anysys-Mode"]&.value
      return if mode.blank?

      credential = Email::CredentialResolver.call(mode: mode)
      Email::DkimSigner.sign!(mail, credential)
    rescue Email::Errors::CredentialsMissing
      # No active credential for this mode — leave the mail unsigned rather than
      # blocking delivery; the missing-credential condition surfaces upstream.
      nil
    ensure
      mail.header["X-Anysys-Mode"] = nil if mail["X-Anysys-Mode"]
    end
  end
end
```

- [ ] **Step 4: Run the spec, verify it passes**

Run: `bundle exec rspec spec/mailers/emails/dkim_interceptor_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/mailers/emails/dkim_interceptor.rb spec/mailers/emails/dkim_interceptor_spec.rb
git commit -m "feat(email): DKIM interceptor (ActionMailer-native signing seam)

Co-Authored-By: Copilot Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: `Emails::DeliveryObserver`

**Files:**
- Create: `app/mailers/emails/delivery_observer.rb`
- Test: `spec/mailers/emails/delivery_observer_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/mailers/emails/delivery_observer_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::DeliveryObserver do
  let(:message) { create(:email_message, :queued) }

  def mail_with_id(id)
    Mail.new do
      to "a@b.com"
      from "s@example.com"
      subject "Hi"
      body "x"
    end.tap { |m| m["X-Anysys-Message-Id"] = id.to_s }
  end

  it "marks the ledger row as sent" do
    described_class.delivered_email(mail_with_id(message.id))
    message.reload
    expect(message.status).to eq("sent")
    expect(message.sent_at).to be_within(1.second).of(Time.current)
  end

  it "is a no-op when the row is missing" do
    expect { described_class.delivered_email(mail_with_id(-1)) }.not_to raise_error
  end

  it "is a no-op when there is no correlation header (foreign mail)" do
    mail = Mail.new { to "a@b.com"; from "s@x.com"; subject "Hi"; body "x" }
    expect { described_class.delivered_email(mail) }.not_to raise_error
  end
end
```

- [ ] **Step 2: Run the spec, verify it fails**

Run: `bundle exec rspec spec/mailers/emails/delivery_observer_spec.rb`
Expected: FAIL — `uninitialized constant Emails::DeliveryObserver`.

- [ ] **Step 3: Implement the observer**

```ruby
# app/mailers/emails/delivery_observer.rb
# frozen_string_literal: true

module Emails
  # ActionMailer delivery observer: flips the Emails::Message ledger row to
  # `sent` after a successful delivery. Fires only on success (observers do not
  # run when delivery raises). Scoped by the X-Anysys-Message-Id header so it
  # ignores all other app mail.
  class DeliveryObserver
    def self.delivered_email(mail)
      id = mail["X-Anysys-Message-Id"]&.value
      return if id.blank?

      message = Emails::Message.find_by(id: id)
      message&.mark_sent!
    end
  end
end
```

- [ ] **Step 4: Run the spec, verify it passes**

Run: `bundle exec rspec spec/mailers/emails/delivery_observer_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/mailers/emails/delivery_observer.rb spec/mailers/emails/delivery_observer_spec.rb
git commit -m "feat(email): delivery observer marks ledger row sent on success

Co-Authored-By: Copilot Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Register hooks + retry config

**Files:**
- Create: `config/initializers/email_delivery.rb`

Note: the interceptor/observer are scoped by `X-Anysys-*` headers, so registering them on `ActionMailer::Base` is safe — they no-op on Billing/Devise/other mail. `to_prepare` re-registers cleanly across code reloads in development. Retry for transient SMTP errors is configured on the framework job (`ActionMailer::MailDeliveryJob`) without subclassing it, matching the retired job's `attempts: 3` intent.

- [ ] **Step 1: Create the initializer**

```ruby
# config/initializers/email_delivery.rb
# frozen_string_literal: true

# Pure-ActionMailer delivery wiring for the Email + Email Campaign modules.
# Both hooks are scoped by the X-Anysys-* headers set in Emails::DeliveryMailer,
# so registering on ActionMailer::Base is safe — they no-op on all other mail.
Rails.application.config.to_prepare do
  ActionMailer::Base.register_interceptor(Emails::DkimInterceptor)
  ActionMailer::Base.register_observer(Emails::DeliveryObserver)
end

# Retry transient SMTP failures on the framework delivery job (no subclass).
# DeliveryMailer's rescue_from has already flipped the ledger row to `failed`
# and re-raised; this gives the send up to 3 attempts with backoff.
ActionMailer::MailDeliveryJob.retry_on(
  Net::SMTPServerBusy, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED,
  wait: :polynomially_longer, attempts: 3
)
```

- [ ] **Step 2: Verify the app boots and hooks register**

Run: `bundle exec rails runner "puts ActionMailer::Base.delivery_interceptors.map(&:name); puts ActionMailer::Base.delivery_observers.map(&:name)"`
Expected output includes `Emails::DkimInterceptor` and `Emails::DeliveryObserver`.

- [ ] **Step 3: Commit**

```bash
git add config/initializers/email_delivery.rb
git commit -m "feat(email): register DKIM interceptor + delivery observer; native retry

Co-Authored-By: Copilot Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Switch `Email::Gateway` + `Email::Activities::Send` to the mailer

**Files:**
- Modify: `app/services/email/gateway.rb` (3 enqueue sites: `send_raw` ~line 45, `queue_for_campaign` ~line 83; the `send` method delegates to `Activities::Send`)
- Modify: `app/services/email/activities/send.rb` (enqueue at step 7, ~line 54)
- Test: extend `spec/services/email/gateway_spec.rb` and `spec/services/email/activities/send_spec.rb`

The enqueue is the **only** change in each method — all ledger/idempotency/credential/rendering logic stays. Replace each:

```ruby
DeliveryJob.perform_later(message.id, mode: mode)   # OLD
```
with:
```ruby
Emails::DeliveryMailer.with(message_id: message.id, mode: mode).deliver_email.deliver_later   # NEW
```

For `queue_for_campaign` (no `mode:` variable in scope) use:
```ruby
Emails::DeliveryMailer.with(message_id: message.id).deliver_email.deliver_later
```

- [ ] **Step 1: Write the failing expectations**

Add to `spec/services/email/activities/send_spec.rb` (inside the existing describe; assumes existing setup creates an active template + credential — reuse the file's existing `let`s):

```ruby
  it "enqueues delivery via DeliveryMailer, not the retired DeliveryJob" do
    expect(Emails::DeliveryMailer).to receive(:with)
      .with(hash_including(message_id: kind_of(Integer)))
      .and_return(double(deliver_email: double(deliver_later: true)))
    described_class.call(customer: customer, to: "r@example.com",
      template_key: template.key, vars: {}, mode: "sandbox")
  end
```

Add to `spec/services/email/gateway_spec.rb` (for `send_raw`):

```ruby
  it "send_raw enqueues via DeliveryMailer" do
    expect(Emails::DeliveryMailer).to receive(:with)
      .and_return(double(deliver_email: double(deliver_later: true)))
    described_class.send_raw(customer: customer, to: "r@example.com",
      subject: "S", body_html: "<p>b</p>", mode: "sandbox")
  end
```

- [ ] **Step 2: Run, verify failure**

Run: `bundle exec rspec spec/services/email/activities/send_spec.rb spec/services/email/gateway_spec.rb`
Expected: FAIL — the new examples expect `Emails::DeliveryMailer` but code still calls `DeliveryJob`.

- [ ] **Step 3: Edit `app/services/email/activities/send.rb`**

Replace the step-7 enqueue line:

```ruby
          # 7. Enqueue delivery (pure ActionMailer)
          Emails::DeliveryMailer.with(message_id: message.id, mode: mode).deliver_email.deliver_later
```

- [ ] **Step 4: Edit `app/services/email/gateway.rb`**

In `send_raw`, replace `DeliveryJob.perform_later(message.id, mode: mode)` with:

```ruby
        Emails::DeliveryMailer.with(message_id: message.id, mode: mode).deliver_email.deliver_later
```

In `queue_for_campaign`, replace `DeliveryJob.perform_later(message.id)` with:

```ruby
        Emails::DeliveryMailer.with(message_id: message.id).deliver_email.deliver_later
```

- [ ] **Step 5: Run the targeted specs, verify pass**

Run: `bundle exec rspec spec/services/email/activities/send_spec.rb spec/services/email/gateway_spec.rb`
Expected: PASS (existing ledger/idempotency/cap examples + the two new enqueue examples).

- [ ] **Step 6: Commit**

```bash
git add app/services/email/gateway.rb app/services/email/activities/send.rb spec/services/email/gateway_spec.rb spec/services/email/activities/send_spec.rb
git commit -m "refactor(email): enqueue sends via DeliveryMailer.deliver_later

Co-Authored-By: Copilot Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Delete the hand-rolled transport

**Files:**
- Delete: `app/services/email/adapters/smtp.rb`, `app/jobs/email/delivery_job.rb`
- Delete: `spec/services/email/adapters/smtp_spec.rb`, `spec/jobs/email/delivery_job_spec.rb`

- [ ] **Step 1: Confirm no remaining references**

Run: `grep -rn "Adapters::Smtp\|DeliveryJob\|Email::DeliveryJob" app spec config lib`
Expected: no matches (Task 5 removed the last callers). If any remain, fix them before deleting.

- [ ] **Step 2: Delete the files**

```bash
git rm app/services/email/adapters/smtp.rb app/jobs/email/delivery_job.rb \
       spec/services/email/adapters/smtp_spec.rb spec/jobs/email/delivery_job_spec.rb
```

Note: `Email::Errors::DeliveryFailed` stays in `app/services/email/errors.rb` (still referenced for failure-code mapping semantics); do not remove it.

- [ ] **Step 3: Run the email + campaign slices, verify green**

Run: `bundle exec rspec spec/mailers/emails spec/services/email spec/jobs/email_campaigns spec/models/emails`
Expected: PASS, no `uninitialized constant` errors.

- [ ] **Step 4: Commit**

```bash
git commit -m "chore(email): remove hand-rolled Mail.new SMTP adapter + DeliveryJob

Co-Authored-By: Copilot Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Clean up dead Trix **editor** assets

**Files:**
- Modify: `app/assets/stylesheets/actiontext.css` (remove editor-chrome rules; keep `.trix-content` display rules)
- Modify: `app/javascript/controllers/template_editor_mode_controller.js`
- Modify: `app/controllers/admin/modules/emails/attachments_controller.rb`

Scope: remove only the Trix **editing-UI** chrome that Lexxy replaces. **Keep** every `.trix-content` rule (these style *displayed* rich text — Lexxy emits the same canonical Action Text HTML) and **keep** `app/views/layouts/action_text/contents/_content.html.erb` unchanged.

- [ ] **Step 1: Strip editor-chrome rules from `actiontext.css`**

Remove every rule block whose selector targets the **editor**: `trix-editor`, `trix-toolbar`, `.trix-button*` (toolbar/buttons/dialogs/in-editor attachment & caption controls — roughly the top of the file through the `trix-editor .attachment__metadata` blocks). **Preserve** the `.trix-content { ... }` section and below (headings, blockquote, lists, pre, img, attachment galleries, the `action-text-attachment` overrides). Update the file's top comment from "Default Trix editor styles" to note it now holds only Action Text **content-display** styles shared by Lexxy.

- [ ] **Step 2: Verify only content-display selectors remain**

Run: `grep -nE "trix-editor|trix-toolbar|trix-button" app/assets/stylesheets/actiontext.css`
Expected: **no matches**.
Run: `grep -c "trix-content" app/assets/stylesheets/actiontext.css`
Expected: a non-zero count (display rules retained).

- [ ] **Step 3: De-Trix the mode controller comments**

In `app/javascript/controllers/template_editor_mode_controller.js`, replace the header comment block so it reads:

```js
// Toggles between the rich_text (Lexxy <lexxy-editor>) and code (raw HTML)
// editor containers when the editor_type <select> value changes.
//
// Targets:
//   select         — the editor_type <select> element
//   richContainer  — the container wrapping the Lexxy rich-text editor
//   codeContainer  — the container wrapping the raw HTML textarea + preview
```

(Logic unchanged — `mode === "rich_text"` etc. stays.)

- [ ] **Step 4: Fix the attachments controller comment**

In `app/controllers/admin/modules/emails/attachments_controller.rb`, change the line-6 comment from `# Tenant-scoped Trix / Action Text attachment upload controller.` to `# Tenant-scoped Lexxy / Action Text attachment upload controller.`

- [ ] **Step 5: Rebuild assets and confirm no Trix-editor references remain**

Run: `grep -rniE "trix-editor|trix-toolbar|trix-button|\(Trix\)|Trix /" app/assets app/javascript app/controllers/admin/modules/emails`
Expected: no matches.

- [ ] **Step 6: Commit**

```bash
git add app/assets/stylesheets/actiontext.css app/javascript/controllers/template_editor_mode_controller.js app/controllers/admin/modules/emails/attachments_controller.rb
git commit -m "chore(email): remove dead Trix editor assets (Lexxy is the editor)

Co-Authored-By: Copilot Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: Full slice verification + browser smoke test

**Files:** none (verification only)

- [ ] **Step 1: Run the full email + campaign spec slices**

Run: `bundle exec rspec spec/mailers/emails spec/services/email spec/services/email_campaigns spec/jobs/email_campaigns spec/models/emails spec/requests/admin/modules/emails`
Expected: PASS (no regressions; the deleted-transport specs are gone, the three new mailer specs pass).

- [ ] **Step 2: Rebuild assets + restart dev server**

Run:
```bash
rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000
```
(If digested assets shadow source per AGENTS.md, run `bin/rails assets:clobber && bin/rails tailwindcss:build` first.)

- [ ] **Step 3: Browser smoke test (real Chromium)**

Open the email template editor (`/:cid/admin/modules/emails/templates/:id/edit`). Confirm:
- `<lexxy-editor>` renders with its toolbar (Lexxy styles, not Trix).
- Existing body content loads into the editor.
- The variable picker inserts `{{token}}` into the editor.
- Switching editor_type to "code" toggles to the HTML textarea + preview.
- Send a test email (preview-to-me) and confirm the ledger row flips to `sent` and the received mail has both text and html parts.
- Open a saved/displayed template render and confirm rich-text content is **still styled** (`.trix-content` rules retained).

- [ ] **Step 4: Final commit (if any verification fixes were needed)**

```bash
git add -A && git commit -m "test(email): verify pure-ActionMailer transport + Lexxy editor

Co-Authored-By: Copilot Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review Notes

- **Spec coverage:** Task 1 ↔ DeliveryMailer (envelope, multipart, headers, native SMTP, tenant blobs, failure). Tasks 2–3 ↔ interceptor/observer. Task 4 ↔ registration + retry. Task 5 ↔ Gateway/Activities enqueue swap. Task 6 ↔ retiring `Adapters::Smtp` + `DeliveryJob`. Task 7 ↔ Trix editor-asset cleanup (editor chrome removed, content-display kept). Task 8 ↔ verification + browser smoke. All spec sections mapped.
- **Preserved behavior:** ledger, idempotency, daily cap, credentials, DKIM gem, campaign fan-out, Lexxy, variable picker, `.trix-content` display styling, content wrapper — none modified.
- **Type/name consistency:** `Emails::DeliveryMailer.with(message_id:, mode:).deliver_email` used identically in Tasks 1, 5; `X-Anysys-Message-Id`/`X-Anysys-Mode` consistent across Tasks 1–4; `mark_sent!`/`mark_failed!(code:, message:)` match `Emails::Message`.
