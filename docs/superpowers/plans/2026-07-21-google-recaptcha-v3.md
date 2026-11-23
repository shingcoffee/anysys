# Google reCAPTCHA v3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate Google reCAPTCHA v3 as a new invisible, score-based Captcha provider.

**Architecture:** Create a `GoogleRecaptchaV3` backend provider extending `Captcha::Providers::Base`, a frontend Stimulus controller to fetch the token invisibly upon action, and i18n configurations. 

**Tech Stack:** Ruby on Rails, StimulusJS, RSpec, Vitest

## Global Constraints

- No hard-coded user-facing strings (must use I18n for both `en` and `zh-CN`).
- 100% test coverage for JS files.
- `access_key_id` translates to Site Key, `access_key_secret` to Secret Key.

---

### Task 1: Add i18n Locales

**Files:**
- Modify: `config/locales/captcha.en.yml`
- Modify: `config/locales/captcha.zh-CN.yml`

**Interfaces:**
- Produces: `captcha.providers.google_recaptcha_v3.name`, `captcha.providers.google_recaptcha_v3.credentials.access_key_id`, `captcha.providers.google_recaptcha_v3.credentials.access_key_secret`

- [ ] **Step 1: Add English locales**

Modify `config/locales/captcha.en.yml` under `en: captcha: providers:`

```yaml
      google_recaptcha_v3:
        name: "Google reCAPTCHA v3"
        credentials:
          access_key_id: "Site Key"
          access_key_secret: "Secret Key"
```

- [ ] **Step 2: Add Chinese locales**

Modify `config/locales/captcha.zh-CN.yml` under `zh-CN: captcha: providers:`

```yaml
      google_recaptcha_v3:
        name: "Google reCAPTCHA v3"
        credentials:
          access_key_id: "Site Key (站点密钥)"
          access_key_secret: "Secret Key (通信密钥)"
```

- [ ] **Step 3: Commit**

```bash
git add config/locales/captcha.en.yml config/locales/captcha.zh-CN.yml
git commit -m "feat: add i18n locales for google recaptcha v3"
```

---

### Task 2: Create Backend Provider and Specs

**Files:**
- Create: `app/services/captcha/providers/google_recaptcha_v3.rb`
- Create: `spec/services/captcha/providers/google_recaptcha_v3_spec.rb`

**Interfaces:**
- Produces: `Captcha::Providers::GoogleRecaptchaV3` class with `.key`, `.configured?`, `.score_based?`, `.widget`, and `#verify`.

- [ ] **Step 1: Write the failing spec**

Create `spec/services/captcha/providers/google_recaptcha_v3_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captcha::Providers::GoogleRecaptchaV3 do
  let(:settings) do
    Captcha::ProviderSettings.new(
      provider: "google_recaptcha_v3",
      access_key_id: "site-key",
      access_key_secret: "secret-key",
      score_threshold: 0.5
    )
  end
  let(:context) { Captcha::VerificationContext.new(verify_param: "token-123", remoteip: "1.2.3.4") }
  let(:provider) { described_class.new(settings: settings) }

  describe ".score_based?" do
    it "returns true" do
      expect(described_class.score_based?).to be(true)
    end
  end

  describe ".configured?" do
    it "returns true when keys are present" do
      expect(described_class.configured?(settings)).to be(true)
    end

    it "returns false when keys are missing" do
      settings.access_key_secret = nil
      expect(described_class.configured?(settings)).to be(false)
    end
  end

  describe "#verify" do
    let(:url) { "https://www.google.com/recaptcha/api/siteverify" }
    
    it "returns success when score is above threshold" do
      stub_request(:post, url).to_return(
        status: 200,
        body: { success: true, score: 0.9, hostname: "example.com" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
      
      result = provider.verify(context: context)
      expect(result[:outcome]).to eq(:success)
      expect(result[:score]).to eq(0.9)
      expect(result[:hostname]).to eq("example.com")
    end

    it "returns invalid when score is below threshold" do
      stub_request(:post, url).to_return(
        status: 200,
        body: { success: true, score: 0.3 }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
      
      result = provider.verify(context: context)
      expect(result[:outcome]).to eq(:invalid)
      expect(result[:score]).to eq(0.3)
    end

    it "returns invalid when success is false" do
      stub_request(:post, url).to_return(
        status: 200,
        body: { success: false, "error-codes" => ["invalid-input-response"] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
      
      result = provider.verify(context: context)
      expect(result[:outcome]).to eq(:invalid)
      expect(result[:score]).to be_nil
    end

    it "returns configuration_error for config related error codes" do
      stub_request(:post, url).to_return(
        status: 200,
        body: { success: false, "error-codes" => ["invalid-input-secret"] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
      
      result = provider.verify(context: context)
      expect(result[:outcome]).to eq(:configuration_error)
    end

    it "returns unreachable for 5xx errors" do
      stub_request(:post, url).to_return(status: 500)
      
      result = provider.verify(context: context)
      expect(result[:outcome]).to eq(:unreachable)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/captcha/providers/google_recaptcha_v3_spec.rb`
Expected: FAIL due to missing class.

- [ ] **Step 3: Implement the provider class**

Create `app/services/captcha/providers/google_recaptcha_v3.rb`:

```ruby
# frozen_string_literal: true

require_relative "../providers"

module Captcha
  module Providers
    class GoogleRecaptchaV3 < Base
      SITEVERIFY_URL = "https://www.google.com/recaptcha/api/siteverify"
      SDK_URL = "https://www.google.com/recaptcha/api.js"

      CONFIG_ERROR_CODES = %w[
        missing-input-secret invalid-input-secret bad-request
      ].freeze

      class << self
        def key                  = "google_recaptcha_v3"
        def default_display_name = "Google reCAPTCHA v3"

        def config_fields = []

        def score_based?
          true
        end

        def configured?(settings)
          settings.access_key_id.present? && settings.access_key_secret.present?
        end

        def widget(settings)
          {
            stimulus_controller: "captcha-google-recaptcha-v3",
            sdk_url:             "#{SDK_URL}?render=#{settings.access_key_id}",
            data: {
              "captcha-google-recaptcha-v3-site-key-value" => settings.access_key_id.to_s
            }
          }
        end
      end

      register!

      def verify(context:)
        with_transport_rescue do
          params = {
            "secret"   => settings.access_key_secret.to_s,
            "response" => context.verify_param
          }
          params["remoteip"] = context.remoteip if context.remoteip.present?

          res, json = http_post_form(SITEVERIFY_URL, params)
          {
            outcome:     map_outcome(res, json),
            http_status: res.code.to_i,
            raw:         json,
            score:       json.is_a?(Hash) ? json["score"] : nil,
            hostname:    json.is_a?(Hash) ? json["hostname"] : nil
          }
        end
      end

      private

      def map_outcome(res, json)
        code = res.code.to_i
        return :unreachable if code >= 500

        if json.is_a?(Hash) && json.key?("success")
          if json["success"] == true
            score = json["score"].to_f
            threshold = settings.score_threshold || 0.5
            return score >= threshold ? :success : :invalid
          end

          codes = Array(json["error-codes"])
          return :configuration_error if (codes & CONFIG_ERROR_CODES).any?

          return :invalid
        end

        code >= 400 ? :configuration_error : :unreachable
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/captcha/providers/google_recaptcha_v3_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/captcha/providers/google_recaptcha_v3.rb spec/services/captcha/providers/google_recaptcha_v3_spec.rb
git commit -m "feat: add google recaptcha v3 backend provider"
```

---

### Task 3: Create Frontend Controller and Vitest Specs

**Files:**
- Create: `app/javascript/controllers/captcha_google_recaptcha_v3_controller.js`
- Create: `spec/javascript/controllers/captcha_google_recaptcha_v3_controller.test.js`

**Interfaces:**
- Consumes: The `grecaptcha` global object and `captcha_widget_component` DOM structure (mount target, input target).

- [ ] **Step 1: Write the failing Vitest spec**

Create `spec/javascript/controllers/captcha_google_recaptcha_v3_controller.test.js`:

```javascript
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/captcha_google_recaptcha_v3_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const html = () => `
  <form>
    <div data-controller="captcha-google-recaptcha-v3"
         data-captcha-google-recaptcha-v3-site-key-value="site-key-1">
      <input type="hidden" data-captcha-google-recaptcha-v3-target="input">
    </div>
    <button type="submit">Go</button>
  </form>`

const flush = () => new Promise((r) => setTimeout(r, 0))

describe("captcha-google-recaptcha-v3 controller", () => {
  let executeMock
  let readyMock

  beforeEach(() => {
    executeMock = vi.fn().mockResolvedValue("TOKEN-XYZ")
    readyMock = vi.fn((cb) => cb())
    window.grecaptcha = { execute: executeMock, ready: readyMock }
  })
  
  afterEach(() => {
    delete window.grecaptcha
    vi.restoreAllMocks()
  })

  it("disables submit button and resolves token on connect if sdk is loaded", async () => {
    const { element } = await mountController("captcha-google-recaptcha-v3", Controller, html())
    await flush()
    
    // Initially disables submit before token
    const submit = document.querySelector("button[type='submit']")
    // We execute grecaptcha in connect -> ready -> execute
    expect(readyMock).toHaveBeenCalledOnce()
    expect(executeMock).toHaveBeenCalledWith("site-key-1", { action: "submit" })
    
    // Wait for the token to be set
    await flush()
    expect(element.querySelector("[data-captcha-google-recaptcha-v3-target='input']").value).toBe("TOKEN-XYZ")
    expect(submit.disabled).toBe(false)
  })

  it("handles grecaptcha errors by leaving form disabled and logging", async () => {
    executeMock.mockRejectedValue(new Error("API Error"))
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {})
    
    await mountController("captcha-google-recaptcha-v3", Controller, html())
    await flush()
    
    const submit = document.querySelector("button[type='submit']")
    expect(submit.disabled).toBe(true)
    expect(warn).toHaveBeenCalled()
  })

  it("tolerates missing input target", async () => {
    const htmlNoInput = `
      <form>
        <div data-controller="captcha-google-recaptcha-v3"
             data-captcha-google-recaptcha-v3-site-key-value="site-key-1">
        </div>
        <button type="submit">Go</button>
      </form>`
    
    await mountController("captcha-google-recaptcha-v3", Controller, htmlNoInput)
    await flush()
    const submit = document.querySelector("button[type='submit']")
    expect(submit.disabled).toBe(false)
  })

  it("tolerates missing form/submit button", async () => {
    const htmlNoForm = `
        <div data-controller="captcha-google-recaptcha-v3"
             data-captcha-google-recaptcha-v3-site-key-value="site-key-1">
          <input type="hidden" data-captcha-google-recaptcha-v3-target="input">
        </div>`
    const { element } = await mountController("captcha-google-recaptcha-v3", Controller, htmlNoForm)
    await flush()
    expect(element.querySelector("[data-captcha-google-recaptcha-v3-target='input']").value).toBe("TOKEN-XYZ")
  })

  it("polls for grecaptcha if not immediately available", async () => {
    delete window.grecaptcha
    vi.useFakeTimers()
    
    const { element } = await mountController("captcha-google-recaptcha-v3", Controller, html())
    
    // Assign after a delay
    window.grecaptcha = { execute: executeMock, ready: readyMock }
    vi.advanceTimersByTime(150)
    await flush()
    
    expect(element.querySelector("[data-captcha-google-recaptcha-v3-target='input']").value).toBe("TOKEN-XYZ")
    vi.useRealTimers()
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run spec/javascript/controllers/captcha_google_recaptcha_v3_controller.test.js`
Expected: FAIL due to missing controller.

- [ ] **Step 3: Implement the Stimulus controller**

Create `app/javascript/controllers/captcha_google_recaptcha_v3_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]
  static values = { siteKey: String }

  connect() {
    this.disableSubmit()
    this.ensureGrecaptcha()
  }

  ensureGrecaptcha() {
    if (window.grecaptcha && window.grecaptcha.ready) {
      this.execute()
    } else {
      setTimeout(() => this.ensureGrecaptcha(), 100)
    }
  }

  execute() {
    window.grecaptcha.ready(() => {
      window.grecaptcha.execute(this.siteKeyValue, { action: "submit" })
        .then((token) => {
          this.setToken(token)
          this.enableSubmit()
        })
        .catch((err) => {
          console.warn("[captcha-google-recaptcha-v3]", err)
        })
    })
  }

  setToken(token) {
    if (this.hasInputTarget) {
      this.inputTarget.value = token
    }
  }

  disableSubmit() {
    if (this.submitButton) {
      this.submitButton.disabled = true
    }
  }

  enableSubmit() {
    if (this.submitButton) {
      this.submitButton.disabled = false
    }
  }

  get submitButton() {
    return this.element.closest("form")?.querySelector("button[type='submit']")
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run spec/javascript/controllers/captcha_google_recaptcha_v3_controller.test.js --coverage`
Expected: PASS with 100% coverage.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/captcha_google_recaptcha_v3_controller.js spec/javascript/controllers/captcha_google_recaptcha_v3_controller.test.js
git commit -m "feat: add google recaptcha v3 stimulus controller"
```
