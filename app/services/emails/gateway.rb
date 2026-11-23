# frozen_string_literal: true

module Emails
  class Gateway
    class << self
      def send(customer:, to:, template_id:, vars:, cc: nil, bcc: nil, reply_to: nil, idempotency_key: nil, mode: nil)
        Activities::Send.call(
          customer:        customer,
          to:              to,
          template_id:     template_id,
          vars:            vars,
          cc:              cc,
          bcc:             bcc,
          reply_to:        reply_to,
          idempotency_key: idempotency_key,
          mode:            mode
        )
      end

      def send_raw(customer:, to:, subject:, body_html:, body_text: nil, cc: nil, bcc: nil, from: nil, reply_to: nil,
                    idempotency_key: nil, mode: nil, attachment_blob_ids: nil)
        idempotency_key = idempotency_key.presence
        existing = PersistMessage.existing(customer_id: customer.id, idempotency_key: idempotency_key)
        return existing if existing

        credential   = Email::CredentialResolver.call(mode: mode || Email::CredentialResolver.default_mode)
        from_address = from || credential.from_address

        # Honour the suppression ledger here too — without this, raw sends
        # (e.g. an admin template test-send) would deliver to hard-bounced /
        # complained addresses, defeating the suppression list and hurting
        # sender reputation. Mirrors Activities::Send and queue_for_send_activity.
        suppressed = Emails::Suppression.suppressed?(customer_id: customer.id, email: to)

        attrs = {
          customer:        customer,
          to:              to,
          from:            from_address,
          cc:              cc,
          bcc:             bcc,
          reply_to:        reply_to,
          subject:         subject,
          body_html:       body_html,
          body_text:       body_text || TemplateRenderer.strip_html(body_html),
          status:          suppressed ? "suppressed" : "queued",
          message_type:    "transactional",
          provider:        credential.provider,
          idempotency_key: idempotency_key,
          delivery_due_at: Time.current,
          metadata:        {
            attachment_blob_ids: Array(attachment_blob_ids),
            tracking_enabled: credential.tracking_enabled?
          }.merge(DeliveryCredential.metadata(credential))
        }

        MessageAdmission.validate!(credential: credential, attributes: attrs)

        if suppressed
          message, _created = Quota.reserve(attrs)
          return message
        end

        message, created = Quota.reserve(attrs)
        DeliveryHandoff.call(message, mode: mode) if created
        message
      end

      # attachment_blob_ids is recipient-independent, so the campaign job
      # computes it once and passes it in; falls back to computing here for
      # standalone callers.
      # `credential:` may be passed by the campaign job so the (batch-invariant)
      # credential is resolved once per run rather than once per recipient.
      def queue_for_send_activity(send_activity:, user:, attachment_blob_ids: nil, idempotency_key: nil, credential: nil,
                                  campaign_limit: Quota::CAMPAIGN_PER_MINUTE)
        idempotency_key = idempotency_key.presence
        if idempotency_key.present?
          existing = Emails::Message.find_by(customer_id: send_activity.customer.id, idempotency_key: idempotency_key)
          return existing if existing
        end

        unless user.customer_id == send_activity.customer_id
          raise Email::Errors::TemplateVarsInvalid, I18n.t("admin_modules.errors.validations.cross_tenant_association")
        end
        template = send_activity.email_template
        unless template&.active? && template.customer_id == send_activity.customer_id
          raise Email::Errors::TemplateVarsInvalid, I18n.t("admin_modules.errors.validations.template_not_active")
        end
        vars     = Emails::VariableContext.for(user: user)
        rendered = TemplateRenderer.render(template: template, vars: vars)
        blob_ids = attachment_blob_ids || Emails::CompileTemplate.blob_ids_for(template)

        credential ||= Email::CredentialResolver.call(mode: Email::CredentialResolver.default_mode)

        MessageAdmission.validate!(credential: credential, attributes: {
          customer: send_activity.customer, to: user.email, message_type: "campaign",
          body_html: rendered[:body_html], metadata: { attachment_blob_ids: blob_ids }
        })

        # Honour the suppression ledger (hard bounces / complaints / unsubscribes)
        # — a suppressed recipient is recorded but never dispatched.
        suppressed = Emails::Suppression.suppressed?(customer_id: send_activity.customer.id, email: user.email)

        message, created = Quota.reserve({
          customer:        send_activity.customer,
          email_template:  template,
          to:              user.email,
          from:            credential.from_address,
          subject:         rendered[:subject],
          body_html:       rendered[:body_html],
          body_text:       rendered[:body_text],
          status:          suppressed ? "suppressed" : "queued",
          message_type:    "campaign",
          provider:        credential.provider,
          email_send_activity_id: send_activity.id,
          idempotency_key: idempotency_key,
          delivery_due_at: Time.current,
          metadata:        {
            send_activity_id:         send_activity.id,
            user_id:             user.id,
            attachment_blob_ids: blob_ids,
            tracking_enabled:    credential.tracking_enabled?
          }.merge(DeliveryCredential.metadata(credential))
        }, campaign_limit: campaign_limit)

        DeliveryHandoff.call(message) if created && !suppressed
        message
      end

    end
  end
end
