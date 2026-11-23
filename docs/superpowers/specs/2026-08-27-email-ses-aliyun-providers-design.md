# Email vendors: AWS SES, Aliyun DirectMail, self-hosted MTA

Date: 2026-08-27

## Problem

The Email module already sends through a vendor-agnostic, platform-scoped credential registry (SMTP + Postmark). The platform owner needs AWS SES and Aliyun DirectMail as first-class API vendors, and an explicit self-hosted MTA path. Tenant admins do not pick a vendor per send.

## Decisions (locked)

1. **Self-hosted MTA** is today's `smtp` vendor. No new key. Display name is renamed in i18n to make that explicit. Existing SMTP credentials keep working. Local DKIM stays SMTP-only.
2. **AWS SES** is the HTTP API (`aws-sdk-sesv2` `SendEmail`) plus bounce/complaint/delivery via SNS on `POST /email/webhooks/ses`.
3. **Aliyun DirectMail** is the REST RPC API (`SingleSendMail` via `Vendor::AliyunRpc`) plus HTTP callback on `POST /email/webhooks/aliyun`. Distinct from Aliyun SMS.
4. **Approach:** two new provider files, official AWS SDK, existing Aliyun signer. No per-vendor migration. No tenant vendor picker. SMTP remains `default!`. Owner disables SMTP to send via SES or Aliyun (same as switching to Postmark today).

## Out of scope

- Replacing Postmark or removing SMTP
- Per-tenant credentials / admin vendor picker
- SES Configuration Sets, dedicated IPs, vendor-hosted templates
- Inbound email / reply routing
- Custom DSN pipeline for SMTP
- SES SMTP interface / Aliyun SMTP interface
- BatchSendMail (the job already sends one `Emails::Message` at a time)

## Architecture

```
Emails::Gateway → Emails::Message → Emails::DeliverMessageJob
                                      → Email::Providers.for(message.provider).deliver
POST /email/webhooks/:provider        → verify_webhook! → parse_events → status + suppression
```

New files:

- `app/services/email/providers/ses.rb` (`key: "ses"`, mechanism `:webhook`)
- `app/services/email/providers/aliyun.rb` (`key: "aliyun"`, mechanism `:webhook`)

Libraries: `aws-sdk-sesv2` (send) and `aws-sdk-sns` (`MessageVerifier`). Aliyun uses `Vendor::AliyunRpc` + `OutboundHttp`. Wrap both behind the provider class.

Credentials stay platform-wide (`Emails::Credential`, unique per provider × mode). Encrypted `password` holds AWS secret access key or Aliyun AccessKeySecret. JSON `config` holds non-secrets. Encrypted `webhook_secret` is used by Aliyun (Postmark-style Basic or `?token=`); SES verifies the SNS certificate and does not use `webhook_secret`.

## Provider contracts

### SES (`Email::Providers::Ses`)

- `config_fields`: `access_key_id`, `region` (default `us-east-1`), `from_email`, optional `sns_topic_arn`
- `configured?`: password + access_key_id + from_email
- `deliver`: `Aws::SESV2::Client#send_email`; store `message_id` as `provider_message_id`
- Map `Aws::SESV2::Errors::ServiceError` → `Email::Errors::ApiError`; network → `TransportError`
- `verify_webhook!`: `Aws::SNS::MessageVerifier` on `request.raw_post`; optional TopicArn match
- `parse_events`: SNS `SubscriptionConfirmation` GETs `SubscribeURL` (HTTPS `sns.*.amazonaws.com` only); `Notification` inner JSON:
  - `Delivery` → `:delivered`
  - `Bounce` with `bounceType == Permanent` → `:bounced`, `suppress: true`; otherwise `:bounced`, `suppress: false`
  - `Complaint` → `:complained`, `suppress: true`
- `uses_webhook_secret?` → false

### Aliyun (`Email::Providers::Aliyun`)

- `config_fields`: `access_key_id`, `region` (default `cn-hangzhou`), `from_email` (DirectMail AccountName), optional `from_alias`
- Endpoint: `https://dm.aliyuncs.com/` for `cn-hangzhou`; `https://dm.{region}.aliyuncs.com/` otherwise. Version `2015-11-23`. Action `SingleSendMail`.
- `configured?`: password + access_key_id + from_email
- `deliver`: form POST of signed RPC params; success returns `EnvId` as `provider_message_id`; non-OK `Code` → `ApiError`
- `ToAddress` is `to` plus present `cc`/`bcc` (DirectMail SingleSendMail has no Cc/Bcc fields)
- `verify_webhook!`: Postmark-style Basic `aliyun:{webhook_secret}` **or** query `token=` matching `webhook_secret`
- `parse_events`: MNS query-string body **or** EventBridge CloudEvents JSON (`data` object):
  - `status` 0 → `:delivered`
  - `status` 2 → `:bounced`, `suppress: true` (invalid address)
  - `status` 3 → `:complained`, `suppress: true`
  - `status` 4 → `:bounced`, `suppress: false`
- Correlate by `env_id` (matches send `EnvId`)

## Supporting changes (not new vendor files)

Multiple API webhook vendors share `emails_credential[from_email]` / webhook_secret in the platform form. Hidden CSS groups still submit. Fix:

- Unique input ids per provider (`emails_credential_<key>_<field>`)
- Disable inputs in hidden provider groups (server-rendered + Stimulus)
- `uses_webhook_secret?` so SES does not render the unused webhook secret field

Document the Email single-file vendor rule in `AGENTS.md` (same shape as Payments / Captcha). SMTP typed columns remain the historical exception.

## Testing

- Provider specs mirroring `spec/services/email/providers/postmark_spec.rb`
- Request specs on `/email/webhooks/ses` and `/email/webhooks/aliyun`
- Credential form component spec still iterates `Email::Providers.all`
- Vitest 100% on `email_credential_form_controller.js` including disable-hidden-groups
- Registry spec includes `:ses` and `:aliyun`

## I18n

`en` + `zh-CN` for provider display names, secret labels, and `config_fields`. SMTP English name becomes `SMTP (self-hosted MTA)`.
