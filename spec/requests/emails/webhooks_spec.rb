# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Emails::Webhooks", type: :request do
  let_it_be(:customer) { create(:customer) }

  let!(:aliyun_credential) do
    create(:email_credential, provider: "aliyun", mode: "sandbox", status: "active",
           host: nil, username: nil, password: "AKS", webhook_secret: "whsec",
           config: { "access_key_id" => "AKID", "from_email" => "noreply@example.com" })
  end

  def basic_auth_header(secret)
    "Basic #{Base64.strict_encode64("aliyun:#{secret}")}"
  end

  def post_webhook(body:, auth: basic_auth_header("whsec"))
    post "/email/webhooks/aliyun", params: body.to_json,
         headers: { "Content-Type" => "application/json", "Authorization" => auth }
  end

  def create_bound_message(*traits, credential: aliyun_credential, **attrs)
    create(:email_message, *traits, **attrs, metadata: { "credential_id" => credential.id, "credential_mode" => credential.mode })
  end

  describe "end-to-end through the real credential-resolution + verification path" do
    it "processes a validly-signed delivery webhook and marks the message delivered" do
      message = create_bound_message(customer: customer, provider: "aliyun",
                       provider_message_id: "env-1", status: "sent")
      post_webhook(body: { "status" => "0", "env_id" => "env-1", "rcpt" => message.to })
      expect(response).to have_http_status(:ok)
      expect(message.reload.status).to eq("delivered")
    end

    it "rejects a forged signature with 403 (resolver + verify run for real)" do
      post_webhook(body: { "status" => "0" }, auth: basic_auth_header("wrong-secret"))
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "multi-key verification across modes (Emails::Message has no mode column)" do
    # A live tenant can have both a sandbox and a production credential active for
    # the same provider, each with its OWN webhook_secret. Since a message can't
    # be tied back to the mode it was sent in, the controller must verify against
    # every active credential and accept whichever secret matches.
    let!(:production_credential) do
      create(:email_credential, provider: "aliyun", mode: "production", status: "active",
             host: nil, username: nil, password: "prod-secret", webhook_secret: "prod-whsec",
             config: { "access_key_id" => "AKID", "from_email" => "noreply@example.com" })
    end

    it "verifies a webhook signed with the NON-default-mode credential's secret when both modes are active" do
      message = create_bound_message(:sent, credential: production_credential, customer: customer, provider: "aliyun", provider_message_id: "env-mode")

      post_webhook(body: { "status" => "0", "env_id" => "env-mode", "rcpt" => message.to },
                   auth: basic_auth_header("prod-whsec"))

      expect(response).to have_http_status(:ok)
      expect(message.reload.status).to eq("delivered")
    end

    it "still rejects a signature matching NEITHER active credential's secret with 403" do
      post_webhook(body: { "status" => "0" }, auth: basic_auth_header("neither-secret"))
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "unknown provider" do
    it "404s — the route itself never matches (constraint on Email::Providers.keys)" do
      post "/email/webhooks/sendgrid", params: {}.to_json, headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:not_found)
    end

    it "404s for the retired postmark provider" do
      post "/email/webhooks/postmark", params: {}.to_json, headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:not_found)
    end

    it "404s for SMTP which has no webhook delivery mechanism" do
      create(:email_credential) unless Emails::Credential.exists?(provider: "smtp", mode: "sandbox")
      post "/email/webhooks/smtp", params: {}.to_json, headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:not_found)
    end
  end

  context "event handling through the real credential-resolution path" do
    describe "signature verification" do
      it "rejects a forged/wrong Authorization header with 403" do
        post_webhook(body: { "status" => "0" }, auth: basic_auth_header("wrong-secret"))
        expect(response).to have_http_status(:forbidden)
      end

      it "rejects a missing Authorization header with 403" do
        post "/email/webhooks/aliyun", params: { "status" => "0" }.to_json,
             headers: { "Content-Type" => "application/json" }
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "delivery events" do
      it "flips a matching message to delivered" do
        msg = create_bound_message(:sent, customer: customer, provider: "aliyun", provider_message_id: "env-100")

        post_webhook(body: { "status" => "0", "env_id" => "env-100", "rcpt" => msg.to })

        expect(response).to have_http_status(:ok)
        expect(msg.reload.status).to eq("delivered")
      end

      it "is a no-op (still 200) when no message matches the provider_message_id" do
        post_webhook(body: { "status" => "0", "env_id" => "unknown-id", "rcpt" => "x@y.com" })
        expect(response).to have_http_status(:ok)
      end

      it "does not transition an unrelated NULL-id message when the event omits env_id (E-BUG-2)" do
        # A message that failed before mark_sent! has provider_message_id NULL.
        orphan = create_bound_message(customer: customer, provider: "aliyun",
                        provider_message_id: nil, status: "queued")

        post_webhook(body: { "status" => "0", "rcpt" => "x@y.com" })

        expect(response).to have_http_status(:ok)
        expect(orphan.reload.status).to eq("queued")
      end

      it "respects the terminal guard — a late delivery event does not resurrect a bounced message" do
        msg = create_bound_message(customer: customer, provider: "aliyun", provider_message_id: "env-101", status: "bounced")

        post_webhook(body: { "status" => "0", "env_id" => "env-101", "rcpt" => msg.to })

        expect(msg.reload.status).to eq("bounced")
      end
    end

    describe "hard-bounce events" do
      it "flips the message to bounced and records a GLOBAL suppression" do
        msg = create_bound_message(:sent, customer: customer, provider: "aliyun", provider_message_id: "env-200",
                     to: "hardbounce@example.com")

        post_webhook(body: {
          "status" => "2", "env_id" => "env-200", "rcpt" => "hardbounce@example.com",
          "err_code" => "SmtpNxBox", "err_msg" => "mailbox does not exist"
        })

        expect(response).to have_http_status(:ok)
        expect(msg.reload.status).to eq("bounced")
        expect(msg.failure_code).to eq("SmtpNxBox")

        suppression = Emails::Suppression.find_by(email: "hardbounce@example.com")
        expect(suppression).to be_present
        expect(suppression.customer_id).to be_nil
        expect(suppression.reason).to eq("hard_bounce")
        expect(suppression.provider).to eq("aliyun")
      end

      it "a subsequent transactional send to the suppressed address is suppressed, not dispatched" do
        post_webhook(body: {
          "status" => "2", "env_id" => "env-201", "rcpt" => "hardbounce2@example.com",
          "err_code" => "SmtpNxBox"
        })

        Current.customer = customer
        template = create(:email_template, customer: customer, name: "welcome")
        result = Emails::Activities::Send.call(customer: customer, to: "hardbounce2@example.com",
                                               template_id: template.id, vars: { name: "Test" })
        expect(result.status).to eq("suppressed")
        Current.customer = nil
      end

      it "a generic failure updates the message but does NOT create a suppression" do
        msg = create_bound_message(:sent, customer: customer, provider: "aliyun", provider_message_id: "env-202",
                     to: "softbounce@example.com")

        post_webhook(body: {
          "status" => "4", "env_id" => "env-202", "rcpt" => "softbounce@example.com",
          "err_code" => "SmtpTxErr"
        })

        expect(msg.reload.status).to eq("bounced")
        expect(Emails::Suppression.find_by(email: "softbounce@example.com")).to be_nil
      end
    end

    describe "spam complaint events" do
      it "flips the message to complained and records a GLOBAL suppression" do
        msg = create_bound_message(:sent, customer: customer, provider: "aliyun", provider_message_id: "env-300",
                     to: "complainer@example.com")

        post_webhook(body: { "status" => "3", "env_id" => "env-300", "rcpt" => "complainer@example.com" })

        expect(response).to have_http_status(:ok)
        expect(msg.reload.status).to eq("complained")

        suppression = Emails::Suppression.find_by(email: "complainer@example.com")
        expect(suppression).to be_present
        expect(suppression.customer_id).to be_nil
        expect(suppression.reason).to eq("complaint")
      end
    end

    describe "multi-tenant isolation" do
      it "updates only the message matching (provider, provider_message_id), never a different tenant's row" do
        other_customer = create(:customer)
        own_msg   = create_bound_message(:sent, customer: customer, provider: "aliyun", provider_message_id: "env-400")
        other_msg = create_bound_message(:sent, customer: other_customer, provider: "aliyun", provider_message_id: "env-401")

        post_webhook(body: { "status" => "0", "env_id" => "env-400", "rcpt" => own_msg.to })

        expect(own_msg.reload.status).to eq("delivered")
        expect(other_msg.reload.status).to eq("sent")
      end
    end
  end

  describe "CredentialsMissing (no retained credential for the provider)" do
    it "returns 503" do
      aliyun_credential.destroy!

      post_webhook(body: { "status" => "0" })
      expect(response).to have_http_status(:service_unavailable)
    end
  end

  describe "verified receipt ownership and retention" do
    context "when two retained modes share the webhook secret" do
      let!(:shared_credential) do
        create(:email_credential, provider: "aliyun", mode: "production", status: "disabled",
               password: "prod-key", webhook_secret: "whsec")
      end

      it "binds to the second recorded mode instead of the first verifying row" do
        message = create_bound_message(:sent, credential: shared_credential, customer: customer,
                                       provider: "aliyun", provider_message_id: "env-shared")

        post_webhook(body: { "status" => "0", "env_id" => "env-shared", "rcpt" => message.to })

        expect(response).to have_http_status(:ok)
        expect(message.reload.status).to eq("delivered")
        expect(Emails::BackendReceipt.last.credential_id).to eq(shared_credential.id)
      end

      it "does not arbitrarily pin an early ambiguous receipt or trust a requested mode" do
        expect {
          post_webhook(body: { "status" => "0", "env_id" => "env-ambiguous", "rcpt" => "early@example.com", "mode" => "production" })
        }.not_to change(Emails::BackendReceipt, :count)
        expect(response).to have_http_status(:conflict)
      end

      it "uses recipient and recorded mode to resolve colliding vendor IDs" do
        first = create_bound_message(:sent, customer: customer, provider: "aliyun", provider_message_id: "env-collision", to: "first@example.com")
        second = create_bound_message(:sent, credential: shared_credential, customer: customer,
                                      provider: "aliyun", provider_message_id: "env-collision", to: "second@example.com")

        post_webhook(body: { "status" => "0", "env_id" => "env-collision", "rcpt" => second.to })

        expect(response).to have_http_status(:ok)
        expect(second.reload.status).to eq("delivered")
        expect(first.reload.status).to eq("sent")
      end

      it "rejects inconsistent stored credential mode instead of guessing an identity" do
        message = create_bound_message(:sent, credential: shared_credential, customer: customer,
                                       provider: "aliyun", provider_message_id: "env-mode-drift")
        message.update!(metadata: { credential_id: shared_credential.id, credential_mode: "sandbox" })

        expect {
          post_webhook(body: { "status" => "0", "env_id" => "env-mode-drift", "rcpt" => message.to })
        }.not_to change(Emails::BackendReceipt, :count)
        expect(response).to have_http_status(:conflict)
        expect(message.reload.status).to eq("sent")
      end
    end

    it "accepts the disabled original credential and deduplicates its receipt" do
      message = create_bound_message(:sent, customer: customer, provider: "aliyun", provider_message_id: "env-disabled")
      aliyun_credential.update!(status: "disabled")
      body = { "status" => "0", "env_id" => "env-disabled", "rcpt" => message.to }

      expect { post_webhook(body: body) }.to change(Emails::BackendReceipt, :count).by(1)
      expect(response).to have_http_status(:ok)
      expect(message.reload.status).to eq("delivered")
      expect(Emails::BackendReceipt.last.credential_id).to eq(aliyun_credential.id)
      expect { post_webhook(body: body) }.not_to change(Emails::BackendReceipt, :count)
    end

    it "never correlates a receipt verified by another credential to the same vendor ID" do
      original = create(:email_credential, provider: "aliyun", mode: "production", status: "disabled",
                        password: "old-key", webhook_secret: "old-webhook")
      message = create_bound_message(:sent, credential: original, customer: customer,
                                     provider: "aliyun", provider_message_id: "env-owned")

      post_webhook(body: { "status" => "0", "env_id" => "env-owned", "rcpt" => message.to })

      expect(response).to have_http_status(:ok)
      expect(message.reload.status).to eq("sent")
      expect(Emails::BackendReceipt.last).to have_attributes(credential_id: aliyun_credential.id, processed_at: nil)
    end

    it "retains early unknown receipts until the vendor ID is committed and reconciled" do
      body = { "status" => "0", "env_id" => "env-before-send", "rcpt" => "early@example.com" }
      post_webhook(body: body)
      receipt = Emails::BackendReceipt.last
      expect(receipt.processed_at).to be_nil
      message = create_bound_message(:queued, customer: customer, provider: "aliyun", to: "early@example.com")
      message.mark_sent!(provider_message_id: "env-before-send")

      Emails::ReceiptInbox.reconcile(provider: "aliyun", vendor_message_id: "env-before-send")

      expect(message.reload.status).to eq("delivered")
      expect(receipt.reload.processed_at).to be_present
    end

    it "does not record a forged callback" do
      expect {
        post_webhook(body: { "status" => "0", "env_id" => "forged" }, auth: basic_auth_header("forged"))
      }.not_to change(Emails::BackendReceipt, :count)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "AWS SES SNS webhooks" do
    let!(:ses_credential) do
      create(:email_credential, provider: "ses", mode: "sandbox", status: "active",
             host: nil, username: nil, password: "secret",
             config: { "access_key_id" => "AKID", "from_email" => "noreply@example.com",
                       "sns_topic_arn" => "arn:aws:sns:us-east-1:1:ses" })
    end

    def sns_envelope(inner)
      { "Type" => "Notification", "TopicArn" => "arn:aws:sns:us-east-1:1:ses",
        "Message" => inner.to_json, "MessageId" => "sns-envelope",
        "Timestamp" => Time.current.iso8601, "SignatureVersion" => "1", "Signature" => "verified-by-sdk-double",
        "SigningCertURL" => "https://sns.us-east-1.amazonaws.com/cert.pem" }
    end

    def post_ses(inner)
      post "/email/webhooks/ses", params: sns_envelope(inner).to_json,
           headers: { "Content-Type" => "application/json" }
    end

    before do
      allow(Aws::SNS::MessageVerifier).to receive(:new)
        .and_return(instance_double(Aws::SNS::MessageVerifier, authentic?: true))
    end

    it "marks a matching message delivered" do
      message = create_bound_message(:sent, credential: ses_credential, customer: customer, provider: "ses",
                       provider_message_id: "ses-1")
      post_ses("notificationType" => "Delivery", "mail" => { "messageId" => "ses-1" },
               "delivery" => { "recipients" => [message.to] })
      expect(response).to have_http_status(:ok)
      expect(message.reload.status).to eq("delivered")
    end

    it "binds a shared-topic notification to the message's recorded production credential" do
      production = create(:email_credential, provider: "ses", mode: "production", status: "disabled", password: "prod-secret",
                          config: { "access_key_id" => "AKID", "from_email" => "noreply@example.com",
                                    "sns_topic_arn" => "arn:aws:sns:us-east-1:1:ses" })
      message = create_bound_message(:sent, credential: production, customer: customer, provider: "ses",
                                     provider_message_id: "ses-shared-topic")

      post_ses("notificationType" => "Delivery", "mail" => { "messageId" => message.provider_message_id, "sendingAccountId" => "1" },
               "delivery" => { "recipients" => [message.to] })

      expect(response).to have_http_status(:ok)
      expect(message.reload.status).to eq("delivered")
      expect(Emails::BackendReceipt.last.credential_id).to eq(production.id)
    end

    it "rejects a verified SNS notification whose sender account differs from the configured topic account" do
      message = create_bound_message(:sent, credential: ses_credential, customer: customer, provider: "ses",
                                     provider_message_id: "ses-wrong-sender")

      expect {
        post_ses("notificationType" => "Delivery", "mail" => { "messageId" => "ses-wrong-sender", "sendingAccountId" => "2" },
                 "delivery" => { "recipients" => [message.to] })
      }.not_to change(Emails::BackendReceipt, :count)

      expect(response).to have_http_status(:forbidden)
      expect(message.reload.status).to eq("sent")
    end

    it "suppresses on a permanent bounce" do
      message = create_bound_message(:sent, credential: ses_credential, customer: customer, provider: "ses",
                       provider_message_id: "ses-2", to: "hard@example.com")
      post_ses("notificationType" => "Bounce", "mail" => { "messageId" => "ses-2" },
               "bounce" => { "bounceType" => "Permanent",
                             "bouncedRecipients" => [{ "emailAddress" => "hard@example.com" }] })
      expect(message.reload.status).to eq("bounced")
      expect(Emails::Suppression.find_by(email: "hard@example.com")).to be_present
    end

    it "rejects a forged SNS signature with 403" do
      allow(Aws::SNS::MessageVerifier).to receive(:new)
        .and_return(instance_double(Aws::SNS::MessageVerifier, authentic?: false))
      post_ses("notificationType" => "Delivery")
      expect(response).to have_http_status(:forbidden)
    end

    it "rejects a JSON array body with 403 instead of raising TypeError" do
      post "/email/webhooks/ses", params: "[]",
           headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 503 when SNS subscription confirmation cannot be fetched" do
      allow(OutboundHttp).to receive(:request)
        .and_raise(OutboundHttp::TransportError, "timeout")

      post "/email/webhooks/ses",
           params: {
              "Type" => "SubscriptionConfirmation",
              "TopicArn" => "arn:aws:sns:us-east-1:1:ses",
              "MessageId" => "subscription-envelope", "Message" => "subscription confirmation", "Token" => "abc",
              "Timestamp" => Time.current.iso8601, "SignatureVersion" => "1", "Signature" => "verified-by-sdk-double",
              "SigningCertURL" => "https://sns.us-east-1.amazonaws.com/cert.pem",
             "SubscribeURL" => "https://sns.us-east-1.amazonaws.com/?Action=ConfirmSubscription&Token=abc"
           }.to_json,
           headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:service_unavailable)
    end
  end
end
