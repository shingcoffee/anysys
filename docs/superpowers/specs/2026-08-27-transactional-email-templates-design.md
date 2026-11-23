# Transactional email templates — design

Date: 2026-08-27

## Problem

System emails are inconsistent: confirmation and passwordless sign-in already use a cream/violet editorial card; reset-password is unstyled Devise; MFA recovery is a leftover indigo button; the six billing notices are raw tables. Recipients judge the product from that inbox moment.

## Decisions (locked with the user)

- **Scope:** confirmation, sign-in link, reset password, MFA recovery, and all six billing templates.
- **Copy:** full premium rewrite, including existing confirmation and sign-in English strings. Specs that asserted literals must follow I18n.
- **Visual:** elevate the existing cream / violet / Georgia editorial shell into one shared chrome. Billing uses the same chrome plus a receipt-style fact block and optional amount highlight — not a second brand.
- **Out of scope:** `Emails::DeliveryMailer` / tenant-authored Email-module HTML; token TTL; recipients; in-app pages; per-tenant branding.

## Architecture

One ViewComponent, `Mailers::ShellComponent`, owns the table layout and inline styles (mail clients cannot load Tailwind). Auth keeps `Authentication::MailerShellComponent` as a thin I18n adapter. MFA and billing views instantiate the shared shell directly.

Chrome regions: hidden preheader → brand lockup (monogram + wordmark) → card (violet + gold hairline) → kicker, title, body → optional amount highlight → optional fact rows → optional CTA + fallback URL → optional note → ignore + footer.

Layout (`mailer.html.erb`) forces light color-scheme so cream/violet is not inverted into unreadable dark-mode.

## Copy & i18n

All user-facing strings go through I18n (`en` + `zh-CN`). New keys are allowed. Existing keys may change (full rewrite). Interpolation variables stay in parity. Tokens never appear in preheader or subject.

## Text parts

Every in-scope HTML mail has a meaning-matched text part (reset-password and billing gain ones).

## Testing

Component specs for the shared shell (CTA, facts, highlight, preheader, blank values). Auth adapter spec covers confirmation / sign-in / reset key parity. Mailer specs assert URLs, subjects, and I18n copy rather than frozen English literals.
