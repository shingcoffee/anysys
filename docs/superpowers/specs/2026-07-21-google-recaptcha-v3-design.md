# Google reCAPTCHA v3 Integration Design

## Overview
Integrate Google reCAPTCHA v3 as a new Captcha provider in the application, offering an invisible, score-based verification experience.

## Architecture & Components
- **Provider Class**: `app/services/captcha/providers/google_recaptcha_v3.rb` extending `Captcha::Providers::Base`.
- **Config Fields**:
  - `site_key` (string): The public site key used in the frontend.
  - `secret_key` (password): The secret key used for backend verification.
  - `score_threshold` (string): The minimum score to consider a success (default "0.5").
- **Frontend Controller**: `app/javascript/controllers/captcha_google_recaptcha_v3_controller.js`
  - Mounts the SDK dynamically.
  - Intercepts form submissions or actions to execute `grecaptcha.execute` and inject the token.

## Data Flow
1. **Frontend**: The Stimulus controller dynamically loads the Google reCAPTCHA v3 JS SDK. Upon a protected action, it retrieves a token via `grecaptcha.execute` and attaches it to the request.
2. **Backend**: The `verify` method calls `https://www.google.com/recaptcha/api/siteverify` using HTTP POST with `secret` and `response` (the token).
3. **Outcome Mapping**:
   - `success: true` and `score >= threshold` -> `:success`
   - `success: false` -> `:invalid` (or `:configuration_error` if error-codes indicate missing/invalid secret)
   - HTTP 4xx/5xx -> `:configuration_error` or `:unreachable`

## Error Handling
- Network timeouts and 5xx responses yield `:unreachable`.
- API responses indicating a malformed secret key yield `:configuration_error`.
- Low scores or invalid tokens yield `:invalid`.

## Testing Strategy
- **Backend Spec**: `spec/services/captcha/providers/google_recaptcha_v3_spec.rb` with WebMock to cover all API outcome scenarios.
- **Frontend Spec**: `spec/javascript/controllers/captcha_google_recaptcha_v3_controller.test.js` using Vitest, mocking `window.grecaptcha`, ensuring 100% line and branch coverage.
