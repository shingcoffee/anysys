# Aliyun Captcha Module — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Protect customer-built member-facing public forms with Aliyun Captcha 2.0 — toggled per-page in the page editor, gated by a customer-level FeatureModule, and verified server-side on `POST /:customer_id/forms/:token` with fail-open on Aliyun outages.

**Architecture:** A self-contained `AliyunCaptcha` namespace owns the entire integration: a singleton platform-credentials model, a Trailblazer Verify activity, an Aliyun HTTP adapter (mirroring `Sms::Adapters::Aliyun`'s RPC HMAC-SHA1 signing), a `before_action` concern on `PublicPagesController`, three ViewComponents (widget, page-editor toggle, platform settings UI), a Stimulus controller for the Aliyun JS SDK, and a `FeatureModules::AliyunCaptcha::Registration`. Per-page toggle state lives in `Page#configuration_json["aliyun_captcha"]["enabled"]`. No new per-page DB column.

**Tech Stack:** Ruby 3.2.8 / Rails 8.1.2 · Trailblazer-Activity · Reform · ViewComponent · TailwindCSS · StimulusJS · RSpec · WebMock · Aliyun OpenAPI v1.0 RPC signing (HMAC-SHA1).

**Spec:** `docs/superpowers/specs/2026-05-12-aliyun-captcha-design.md`

---

## File Map

### Created

```
app/models/aliyun_captcha/
  platform_settings.rb

app/services/aliyun_captcha/
  errors.rb
  gateway.rb
  adapters/
    base.rb
    aliyun.rb
  contracts/
    verify.rb
    platform_settings.rb
  activities/
    verify.rb
    update_platform_settings.rb

app/services/feature_modules/aliyun_captcha/
  registration.rb
  provisioner.rb

app/controllers/concerns/
  aliyun_captcha_protectable.rb

app/controllers/admin/maintenance/platform/aliyun_captcha/
  settings_controller.rb

app/controllers/admin/settings/modules/aliyun_captcha/
  status_controller.rb

app/components/aliyun_captcha/
  widget_component.rb
  widget_component.html.erb
  page_editor_toggle_component.rb
  page_editor_toggle_component.html.erb

app/components/admin/maintenance/platform/aliyun_captcha/
  settings_component.rb
  settings_component.html.erb

app/components/admin/settings/modules/aliyun_captcha/
  status_component.rb
  status_component.html.erb

app/views/admin/maintenance/platform/aliyun_captcha/settings/
  show.html.erb
  edit.html.erb

app/views/admin/settings/modules/aliyun_captcha/status/
  show.html.erb

app/javascript/controllers/
  aliyun_captcha_controller.js

config/locales/
  aliyun_captcha.en.yml
  aliyun_captcha.zh-CN.yml

db/migrate/
  YYYYMMDDHHMMSS_create_aliyun_captcha_platform_settings.rb

spec/factories/
  aliyun_captcha_platform_settings.rb

spec/models/aliyun_captcha/
  platform_settings_spec.rb

spec/services/aliyun_captcha/
  gateway_spec.rb
  adapters/aliyun_spec.rb
  activities/verify_spec.rb
  activities/update_platform_settings_spec.rb

spec/services/feature_modules/aliyun_captcha/
  registration_spec.rb
  provisioner_spec.rb

spec/controllers/admin/maintenance/platform/aliyun_captcha/
  settings_controller_spec.rb

spec/controllers/admin/settings/modules/aliyun_captcha/
  status_controller_spec.rb

spec/components/aliyun_captcha/
  widget_component_spec.rb
  page_editor_toggle_component_spec.rb

spec/concerns/
  aliyun_captcha_protectable_spec.rb

spec/requests/
  public_pages_aliyun_captcha_spec.rb
```

### Modified

```
app/controllers/public_pages_controller.rb        — include concern + before_action :verify_aliyun_captcha!
app/models/page.rb                                — add #aliyun_captcha_enabled? + writer
app/views/admin/maintenance/pages/_editor.html.erb — render PageEditorToggleComponent inside form_settings section
app/views/public_page.html.erb (layout) OR        — render WidgetComponent above submit button (exact view confirmed in Task 14)
  the page-content template that renders submit button
config/routes.rb                                  — two new routes (platform settings + customer status)
spec/controllers/public_pages_controller_spec.rb  — adjusted only if it conflicts with new captcha behavior (verified in Task 16)
```

---

## Task 1: Database — `aliyun_captcha_platform_settings` migration & model

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_create_aliyun_captcha_platform_settings.rb` (timestamp from `bin/rails g`)
- Create: `app/models/aliyun_captcha/platform_settings.rb`
- Create: `spec/factories/aliyun_captcha_platform_settings.rb`
- Test: `spec/models/aliyun_captcha/platform_settings_spec.rb`

- [ ] **Step 1: Generate migration**

Run:
```bash
bin/rails generate migration CreateAliyunCaptchaPlatformSettings
```

- [ ] **Step 2: Fill migration body**

Replace generated migration body:

```ruby
class CreateAliyunCaptchaPlatformSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :aliyun_captcha_platform_settings do |t|
      t.string  :access_key_id
      t.text    :access_key_secret           # AR encrypts at rest
      t.string  :scene_id
      t.string  :endpoint, null: false, default: "captcha.cn-shanghai.aliyuncs.com"
      t.string  :region,   null: false, default: "cn-shanghai"
      t.boolean :enabled,  null: false, default: false
      t.datetime :last_health_check_at
      t.string   :last_health_check_status   # "ok" | "configuration_error" | "unreachable"
      t.string   :last_health_check_message
      t.timestamps
    end
  end
end
```

- [ ] **Step 3: Run migration**

Run:
```bash
bin/rails db:migrate
```

Expected: `== CreateAliyunCaptchaPlatformSettings: migrated`.

- [ ] **Step 4: Write the failing test**

Create `spec/models/aliyun_captcha/platform_settings_spec.rb`:

```ruby
# frozen_string_literal: true
require "rails_helper"

RSpec.describe AliyunCaptcha::PlatformSettings do
  describe ".instance" do
    it "returns a single row, creating it on first call" do
      expect(described_class.count).to eq(0)
      first  = described_class.instance
      second = described_class.instance
      expect(first).to eq(second)
      expect(described_class.count).to eq(1)
    end
  end

  describe "validations" do
    it "rejects a second row" do
      described_class.instance
      duplicate = described_class.new(access_key_id: "x", access_key_secret: "y", scene_id: "s")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:base]).to include(match(/only one/i))
    end
  end

  describe "credential encryption" do
    it "encrypts access_key_secret at rest" do
      s = described_class.instance
      s.update!(access_key_id: "AKID", access_key_secret: "SECRET", scene_id: "scn")
      raw = ActiveRecord::Base.connection.execute(
        "SELECT access_key_secret FROM aliyun_captcha_platform_settings WHERE id=#{s.id}"
      ).first
      stored = raw.is_a?(Hash) ? raw["access_key_secret"] : raw[0]
      expect(stored).not_to include("SECRET")
      expect(s.reload.access_key_secret).to eq("SECRET")
    end
  end

  describe "#configured?" do
    it "is false when any credential field is blank" do
      s = described_class.instance
      expect(s.configured?).to eq(false)
      s.update!(access_key_id: "AKID", access_key_secret: "", scene_id: "scn")
      expect(s.configured?).to eq(false)
      s.update!(access_key_secret: "S")
      expect(s.configured?).to eq(true)
    end
  end
end
```

- [ ] **Step 5: Run the test, expect failure**

Run:
```bash
bin/rspec spec/models/aliyun_captcha/platform_settings_spec.rb
```

Expected: `NameError: uninitialized constant AliyunCaptcha::PlatformSettings`.

- [ ] **Step 6: Implement the model**

Create `app/models/aliyun_captcha/platform_settings.rb`:

```ruby
# frozen_string_literal: true

module AliyunCaptcha
  # Singleton row holding platform-wide Aliyun Captcha credentials.
  # Accessed via .instance — never instantiate directly outside this class.
  class PlatformSettings < ApplicationRecord
    self.table_name = "aliyun_captcha_platform_settings"

    encrypts :access_key_secret

    validate :only_one_row_allowed

    def self.instance
      first || create!(access_key_id: nil, access_key_secret: nil, scene_id: nil)
    end

    def configured?
      access_key_id.present? && access_key_secret.present? && scene_id.present?
    end

    private

    def only_one_row_allowed
      return unless self.class.where.not(id: id).exists?

      errors.add(:base, "only one AliyunCaptcha::PlatformSettings row is allowed")
    end
  end
end
```

- [ ] **Step 7: Add factory**

Create `spec/factories/aliyun_captcha_platform_settings.rb`:

```ruby
# frozen_string_literal: true
FactoryBot.define do
  factory :aliyun_captcha_platform_settings, class: "AliyunCaptcha::PlatformSettings" do
    access_key_id     { "AKID-test" }
    access_key_secret { "SECRET-test" }
    scene_id          { "1ab23cde" }
    endpoint          { "captcha.cn-shanghai.aliyuncs.com" }
    region            { "cn-shanghai" }
    enabled           { true }
  end
end
```

- [ ] **Step 8: Run the test, expect pass**

Run:
```bash
bin/rspec spec/models/aliyun_captcha/platform_settings_spec.rb
```

Expected: 4 examples, 0 failures.

- [ ] **Step 9: Commit**

```bash
git add db/migrate db/schema.rb app/models/aliyun_captcha spec/factories/aliyun_captcha_platform_settings.rb spec/models/aliyun_captcha/platform_settings_spec.rb
git commit -m "feat(aliyun_captcha): platform settings singleton model"
```

---

## Task 2: Errors namespace + adapter base

**Files:**
- Create: `app/services/aliyun_captcha/errors.rb`
- Create: `app/services/aliyun_captcha/adapters/base.rb`

- [ ] **Step 1: Create errors module**

`app/services/aliyun_captcha/errors.rb`:

```ruby
# frozen_string_literal: true

module AliyunCaptcha
  module Errors
    class Error              < StandardError; end
    class CredentialsMissing < Error; end
    class ConfigurationError < Error; end   # 4xx vendor responses
    class TransportError     < Error; end   # 5xx, timeouts, network
  end
end
```

- [ ] **Step 2: Create adapter base**

`app/services/aliyun_captcha/adapters/base.rb`:

```ruby
# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module AliyunCaptcha
  module Adapters
    class Base
      OPEN_TIMEOUT = 2
      READ_TIMEOUT = 3

      def initialize(settings:)
        @settings = settings
      end

      def verify(verify_param:)
        raise NotImplementedError
      end

      protected

      attr_reader :settings

      def http_post_form(url, params)
        uri = URI(url)
        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/x-www-form-urlencoded"
        req.body = URI.encode_www_form(params)
        do_request(uri, req)
      end

      def do_request(uri, req)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        res = http.request(req)
        json = safe_json(res.body)
        [res, json]
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, Errno::ETIMEDOUT, SocketError => e
        raise AliyunCaptcha::Errors::TransportError, e.message
      end

      def safe_json(str)
        JSON.parse(str.to_s)
      rescue JSON::ParserError
        { "raw" => str.to_s }
      end
    end
  end
end
```

- [ ] **Step 3: Commit**

```bash
git add app/services/aliyun_captcha/errors.rb app/services/aliyun_captcha/adapters/base.rb
git commit -m "feat(aliyun_captcha): errors namespace and HTTP adapter base"
```

---

## Task 3: Aliyun adapter — RPC HMAC-SHA1 signing + verify call

**Files:**
- Create: `app/services/aliyun_captcha/adapters/aliyun.rb`
- Test: `spec/services/aliyun_captcha/adapters/aliyun_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/services/aliyun_captcha/adapters/aliyun_spec.rb`:

```ruby
# frozen_string_literal: true
require "rails_helper"
require "webmock/rspec"

RSpec.describe AliyunCaptcha::Adapters::Aliyun do
  let(:settings) do
    build_stubbed(:aliyun_captcha_platform_settings,
                  access_key_id: "AKID",
                  access_key_secret: "AKS",
                  scene_id: "scene-1",
                  endpoint: "captcha.cn-shanghai.aliyuncs.com",
                  region: "cn-shanghai")
  end
  let(:adapter)  { described_class.new(settings: settings) }
  let(:endpoint) { "https://captcha.cn-shanghai.aliyuncs.com/" }

  describe "#verify" do
    it "POSTs Action=VerifyIntelligentCaptcha with CaptchaVerifyParam and SceneId" do
      stub_request(:post, endpoint).to_return(
        status: 200,
        body: { "Code" => "Success", "Result" => { "VerifyResult" => true } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      result = adapter.verify(verify_param: "{\"captchaVerifyToken\":\"t\"}")

      expect(result).to eq(outcome: :success, http_status: 200, raw: { "Code" => "Success", "Result" => { "VerifyResult" => true } })
      expect(WebMock).to have_requested(:post, endpoint).with { |req|
        body = URI.decode_www_form(req.body).to_h
        body["Action"]             == "VerifyIntelligentCaptcha" &&
          body["SceneId"]          == "scene-1" &&
          body["CaptchaVerifyParam"] == "{\"captchaVerifyToken\":\"t\"}" &&
          body["AccessKeyId"]      == "AKID" &&
          body["SignatureMethod"]  == "HMAC-SHA1" &&
          body["SignatureVersion"] == "1.0" &&
          body["Format"]           == "JSON" &&
          body["Version"]          == "2023-03-05" &&
          body["Signature"].present?
      }
    end

    it "maps VerifyResult=false to :invalid" do
      stub_request(:post, endpoint).to_return(
        status: 200,
        body: { "Code" => "Success", "Result" => { "VerifyResult" => false } }.to_json
      )
      expect(adapter.verify(verify_param: "{}")).to include(outcome: :invalid)
    end

    it "maps HTTP 4xx (e.g. InvalidAccessKeyId) to :configuration_error" do
      stub_request(:post, endpoint).to_return(
        status: 400,
        body: { "Code" => "InvalidAccessKeyId.NotFound", "Message" => "key not found" }.to_json
      )
      out = adapter.verify(verify_param: "{}")
      expect(out[:outcome]).to eq(:configuration_error)
      expect(out[:http_status]).to eq(400)
    end

    it "maps HTTP 5xx to :unreachable" do
      stub_request(:post, endpoint).to_return(status: 503, body: "")
      expect(adapter.verify(verify_param: "{}")[:outcome]).to eq(:unreachable)
    end

    it "maps a timeout to :unreachable" do
      stub_request(:post, endpoint).to_timeout
      expect(adapter.verify(verify_param: "{}")[:outcome]).to eq(:unreachable)
    end

    it "computes a deterministic signature for a known input (golden test)" do
      # Lock the non-deterministic params, then assert the resulting signature.
      allow(SecureRandom).to receive(:uuid).and_return("nonce-fixed")
      allow(Time).to receive(:now).and_return(Time.utc(2026, 5, 12, 12, 0, 0))

      params = adapter.send(:sign_params, adapter.send(:common_params).merge(
        "Action"             => "VerifyIntelligentCaptcha",
        "SceneId"            => "scene-1",
        "CaptchaVerifyParam" => "{}"
      ))

      # Recompute the expected signature with the same algorithm to anchor a regression test.
      sorted = params.except("Signature").sort.map { |k, v|
        kp = CGI.escape(k.to_s).gsub("+", "%20").gsub("*", "%2A").gsub("%7E", "~")
        vp = CGI.escape(v.to_s).gsub("+", "%20").gsub("*", "%2A").gsub("%7E", "~")
        "#{kp}=#{vp}"
      }.join("&")
      to_sign  = "POST&%2F&" + CGI.escape(sorted).gsub("+", "%20").gsub("*", "%2A").gsub("%7E", "~")
      expected = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA1", "AKS&", to_sign))

      expect(params["Signature"]).to eq(expected)
    end
  end
end
```

- [ ] **Step 2: Run the test, expect failure**

Run:
```bash
bin/rspec spec/services/aliyun_captcha/adapters/aliyun_spec.rb
```

Expected: `NameError: uninitialized constant AliyunCaptcha::Adapters::Aliyun`.

- [ ] **Step 3: Implement the adapter**

Create `app/services/aliyun_captcha/adapters/aliyun.rb`:

```ruby
# frozen_string_literal: true

require "openssl"
require "base64"
require "securerandom"
require "cgi"

module AliyunCaptcha
  module Adapters
    # Aliyun Captcha 2.0 adapter (RPC-style, HMAC-SHA1, v1.0 signing — same
    # rules as Sms::Adapters::Aliyun).
    #
    # Outcomes:
    #   :success              -> 200 + Result.VerifyResult == true
    #   :invalid              -> 200 + Result.VerifyResult == false
    #   :configuration_error  -> HTTP 4xx
    #   :unreachable          -> HTTP 5xx, timeout, network error
    class Aliyun < Base
      VERSION = "2023-03-05"

      def verify(verify_param:)
        params = common_params.merge(
          "Action"             => "VerifyIntelligentCaptcha",
          "SceneId"            => settings.scene_id.to_s,
          "CaptchaVerifyParam" => verify_param.to_s
        )
        res, json = http_post_form(host_url, sign_params(params))
        { outcome: map_outcome(res, json), http_status: res.code.to_i, raw: json }
      rescue AliyunCaptcha::Errors::TransportError
        { outcome: :unreachable, http_status: nil, raw: nil }
      end

      # Exposed for the golden signing test.
      def sign_params(params)
        params.merge("Signature" => compute_signature(params))
      end

      private

      def host_url
        "https://#{settings.endpoint}/"
      end

      def common_params
        {
          "AccessKeyId"      => settings.access_key_id.to_s,
          "Format"           => "JSON",
          "RegionId"         => settings.region.to_s,
          "SignatureMethod"  => "HMAC-SHA1",
          "SignatureNonce"   => SecureRandom.uuid,
          "SignatureVersion" => "1.0",
          "Timestamp"        => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
          "Version"          => VERSION
        }
      end

      def compute_signature(params)
        sorted  = params.sort.map { |k, v| "#{pct(k)}=#{pct(v)}" }.join("&")
        to_sign = "POST&#{pct('/')}&#{pct(sorted)}"
        key     = settings.access_key_secret.to_s + "&"
        Base64.strict_encode64(OpenSSL::HMAC.digest("SHA1", key, to_sign))
      end

      def pct(str)
        CGI.escape(str.to_s).gsub("+", "%20").gsub("*", "%2A").gsub("%7E", "~")
      end

      def map_outcome(res, json)
        code = res.code.to_i
        return :unreachable          if code >= 500
        return :configuration_error  if code >= 400
        return :success              if json.dig("Result", "VerifyResult") == true
        :invalid
      end
    end
  end
end
```

- [ ] **Step 4: Run the test, expect pass**

Run:
```bash
bin/rspec spec/services/aliyun_captcha/adapters/aliyun_spec.rb
```

Expected: 5 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/services/aliyun_captcha/adapters/aliyun.rb spec/services/aliyun_captcha/adapters/aliyun_spec.rb
git commit -m "feat(aliyun_captcha): Aliyun adapter with HMAC-SHA1 signing and outcome mapping"
```

---

## Task 4: Verify contract + activity

**Files:**
- Create: `app/services/aliyun_captcha/contracts/verify.rb`
- Create: `app/services/aliyun_captcha/activities/verify.rb`
- Test: `spec/services/aliyun_captcha/activities/verify_spec.rb`

- [ ] **Step 1: Write the failing test**

`spec/services/aliyun_captcha/activities/verify_spec.rb`:

```ruby
# frozen_string_literal: true
require "rails_helper"

RSpec.describe AliyunCaptcha::Activities::Verify do
  let!(:settings) { create(:aliyun_captcha_platform_settings) }

  def stub_adapter(outcome:, http_status: 200, raw: {})
    instance = instance_double(AliyunCaptcha::Adapters::Aliyun,
                               verify: { outcome: outcome, http_status: http_status, raw: raw })
    allow(AliyunCaptcha::Adapters::Aliyun).to receive(:new).and_return(instance)
    instance
  end

  it "returns :invalid when verify_param is blank" do
    result = described_class.call(verify_param: "")
    expect(result.outcome).to eq(:invalid)
    expect(result.success?).to eq(false)
  end

  it "returns :disabled when settings are not configured" do
    settings.update!(access_key_id: nil, access_key_secret: nil, scene_id: nil)
    result = described_class.call(verify_param: "{}")
    expect(result.outcome).to eq(:disabled)
    expect(result.success?).to eq(true)   # caller treats disabled as fail-open
  end

  it "delegates to the adapter and maps :success" do
    stub_adapter(outcome: :success)
    result = described_class.call(verify_param: "{}")
    expect(result.outcome).to eq(:success)
    expect(result.success?).to eq(true)
  end

  %i[invalid unreachable configuration_error].each do |outcome|
    it "passes through :#{outcome} from the adapter" do
      stub_adapter(outcome: outcome)
      expect(described_class.call(verify_param: "{}").outcome).to eq(outcome)
    end
  end

  it "emits an ActiveSupport::Notifications event with outcome" do
    stub_adapter(outcome: :success, http_status: 200)
    events = []
    ActiveSupport::Notifications.subscribed(->(*args) { events << ActiveSupport::Notifications::Event.new(*args) },
                                            "aliyun_captcha.verify") do
      described_class.call(verify_param: "{}")
    end
    expect(events.size).to eq(1)
    expect(events.first.payload[:outcome]).to eq(:success)
    expect(events.first.payload[:http_status]).to eq(200)
  end

  it "records last_health_check_status on the settings row" do
    stub_adapter(outcome: :configuration_error, http_status: 400, raw: { "Message" => "bad key" })
    described_class.call(verify_param: "{}")
    expect(settings.reload.last_health_check_status).to eq("configuration_error")
    expect(settings.reload.last_health_check_at).to be_present
  end
end
```

- [ ] **Step 2: Run the test, expect failure**

Run:
```bash
bin/rspec spec/services/aliyun_captcha/activities/verify_spec.rb
```

Expected: `NameError: uninitialized constant AliyunCaptcha::Activities::Verify`.

- [ ] **Step 3: Implement the contract**

`app/services/aliyun_captcha/contracts/verify.rb`:

```ruby
# frozen_string_literal: true

require "reform"
require "reform/form/dry"

module AliyunCaptcha
  module Contracts
    class Verify < Reform::Form
      property :verify_param
      validates :verify_param, presence: true
    end
  end
end
```

- [ ] **Step 4: Implement the activity**

`app/services/aliyun_captcha/activities/verify.rb`:

```ruby
# frozen_string_literal: true

module AliyunCaptcha
  module Activities
    class Verify
      Result = Struct.new(:outcome, :raw, :http_status, keyword_init: true) do
        # Outcomes that should NOT block the request:
        #   :success                  — captcha verified
        #   :unreachable              — Aliyun unreachable (fail-open)
        #   :configuration_error      — 4xx from Aliyun (fail-open, surface to platform owner)
        #   :disabled                 — credentials missing (fail-open)
        # Blocking outcome:
        #   :invalid                  — token rejected by Aliyun
        def success?
          outcome != :invalid
        end
      end

      def self.call(verify_param:)
        contract = AliyunCaptcha::Contracts::Verify.new(OpenStruct.new(verify_param: verify_param))
        unless contract.validate(verify_param: verify_param)
          return finalize(Result.new(outcome: :invalid, raw: nil, http_status: nil), settings: nil)
        end

        settings = AliyunCaptcha::PlatformSettings.instance
        unless settings.configured?
          return finalize(Result.new(outcome: :disabled, raw: nil, http_status: nil), settings: settings)
        end

        adapter = AliyunCaptcha::Adapters::Aliyun.new(settings: settings)
        adapter_result = nil
        duration = Benchmark.realtime { adapter_result = adapter.verify(verify_param: verify_param) }

        result = Result.new(
          outcome:     adapter_result[:outcome],
          raw:         adapter_result[:raw],
          http_status: adapter_result[:http_status]
        )
        instrument(result, duration)
        finalize(result, settings: settings)
      end

      def self.instrument(result, duration)
        ActiveSupport::Notifications.instrument(
          "aliyun_captcha.verify",
          duration: duration, outcome: result.outcome, http_status: result.http_status
        )
      end

      def self.finalize(result, settings:)
        return result if settings.nil? || result.outcome == :disabled

        status = case result.outcome
                 when :success              then "ok"
                 when :configuration_error  then "configuration_error"
                 when :unreachable          then "unreachable"
                 else                            settings.last_health_check_status
                 end
        message = result.raw.is_a?(Hash) ? (result.raw["Message"] || result.raw["message"]).to_s.presence : nil
        settings.update_columns(
          last_health_check_at:      Time.current,
          last_health_check_status:  status,
          last_health_check_message: message
        )
        result
      end
    end
  end
end
```

- [ ] **Step 5: Run the test, expect pass**

Run:
```bash
bin/rspec spec/services/aliyun_captcha/activities/verify_spec.rb
```

Expected: 7 examples, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/services/aliyun_captcha/contracts app/services/aliyun_captcha/activities/verify.rb spec/services/aliyun_captcha/activities/verify_spec.rb
git commit -m "feat(aliyun_captcha): Verify contract and activity with health-check side effects"
```

---

## Task 5: Gateway facade + spec

**Files:**
- Create: `app/services/aliyun_captcha/gateway.rb`
- Test: `spec/services/aliyun_captcha/gateway_spec.rb`

- [ ] **Step 1: Write the failing test**

`spec/services/aliyun_captcha/gateway_spec.rb`:

```ruby
# frozen_string_literal: true
require "rails_helper"

RSpec.describe AliyunCaptcha::Gateway do
  describe ".verify" do
    it "delegates to AliyunCaptcha::Activities::Verify with verify_param" do
      expect(AliyunCaptcha::Activities::Verify).to receive(:call)
        .with(verify_param: "abc").and_return(:result)
      expect(described_class.verify(verify_param: "abc")).to eq(:result)
    end
  end
end
```

- [ ] **Step 2: Run the test, expect failure**

Run:
```bash
bin/rspec spec/services/aliyun_captcha/gateway_spec.rb
```

Expected: `NameError: uninitialized constant AliyunCaptcha::Gateway`.

- [ ] **Step 3: Implement gateway**

`app/services/aliyun_captcha/gateway.rb`:

```ruby
# frozen_string_literal: true

module AliyunCaptcha
  # Single public entry-point for host code that wants to verify a captcha
  # outside of the controller filter (rare). The controller filter calls the
  # activity directly.
  class Gateway
    def self.verify(verify_param:)
      AliyunCaptcha::Activities::Verify.call(verify_param: verify_param)
    end
  end
end
```

- [ ] **Step 4: Run the test, expect pass**

Run:
```bash
bin/rspec spec/services/aliyun_captcha/gateway_spec.rb
```

Expected: 1 example, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/services/aliyun_captcha/gateway.rb spec/services/aliyun_captcha/gateway_spec.rb
git commit -m "feat(aliyun_captcha): public gateway facade"
```

---

## Task 6: FeatureModule registration + provisioner

**Files:**
- Create: `app/services/feature_modules/aliyun_captcha/registration.rb`
- Create: `app/services/feature_modules/aliyun_captcha/provisioner.rb`
- Test: `spec/services/feature_modules/aliyun_captcha/registration_spec.rb`
- Test: `spec/services/feature_modules/aliyun_captcha/provisioner_spec.rb`

- [ ] **Step 1: Write the failing registration test**

`spec/services/feature_modules/aliyun_captcha/registration_spec.rb`:

```ruby
# frozen_string_literal: true
require "rails_helper"

RSpec.describe FeatureModules::AliyunCaptcha::Registration do
  describe ".register!" do
    it "creates or updates the FeatureModules::Module row with key 'aliyun_captcha'" do
      described_class.register!
      fm = FeatureModules::Module.find_by(key: "aliyun_captcha")
      expect(fm).to be_present
      expect(fm.name).to eq("Aliyun Captcha")
      expect(fm).to be_active
      expect(fm.required).to eq(false)
    end
  end

  describe ".sidebar_contributions" do
    it "exposes the customer settings link" do
      contributions = described_class.sidebar_contributions(double("controller"))
      labels = contributions[:settings].map(&:label)
      expect(labels).to include("Aliyun Captcha")
    end
  end
end
```

- [ ] **Step 2: Write the failing provisioner test**

`spec/services/feature_modules/aliyun_captcha/provisioner_spec.rb`:

```ruby
# frozen_string_literal: true
require "rails_helper"

RSpec.describe FeatureModules::AliyunCaptcha::Provisioner do
  let(:customer) { create(:customer) }

  describe ".call" do
    it "is a no-op (returns nil)" do
      expect(described_class.call(customer)).to be_nil
    end
  end

  describe ".deprovision" do
    it "strips aliyun_captcha.enabled from each Page#configuration_json for the customer" do
      page1 = create(:page, customer: customer)
      page1.configuration_json = page1.configuration_json.merge(
        "aliyun_captcha" => { "enabled" => true }
      )
      page1.save!(validate: false)

      described_class.deprovision(customer)

      expect(page1.reload.configuration_json["aliyun_captcha"]).to be_nil
    end
  end
end
```

- [ ] **Step 3: Run both tests, expect failure**

Run:
```bash
bin/rspec spec/services/feature_modules/aliyun_captcha
```

Expected: `NameError: uninitialized constant FeatureModules::AliyunCaptcha::Registration`.

- [ ] **Step 4: Implement provisioner**

`app/services/feature_modules/aliyun_captcha/provisioner.rb`:

```ruby
# frozen_string_literal: true

module FeatureModules
  module AliyunCaptcha
    class Provisioner
      def self.call(_customer)
        nil   # nothing per-tenant to set up
      end

      def self.deprovision(customer)
        Page.unscoped.where(customer_id: customer.id).find_each do |page|
          config = page.configuration_json
          next unless config.is_a?(Hash) && config.key?("aliyun_captcha")

          config = config.except("aliyun_captcha")
          page.configuration_json = config
          page.save!(validate: false)
        end
      end
    end
  end
end
```

- [ ] **Step 5: Implement registration**

`app/services/feature_modules/aliyun_captcha/registration.rb`:

```ruby
# frozen_string_literal: true

module FeatureModules
  module AliyunCaptcha
    class Registration < FeatureModules::BaseModule
      def self.module_key         = "aliyun_captcha"
      def self.module_name        = "Aliyun Captcha"
      def self.module_description = "Protect customer-facing public forms with Aliyun Captcha 2.0"

      def self.provision!(customer)   = Provisioner.call(customer)
      def self.deprovision!(customer) = Provisioner.deprovision(customer)

      entry_path { |customer| "/#{customer.id}/admin/settings/modules/aliyun_captcha" }
      default_exit kind: "route", name: "customer_home"

      def self.sidebar_contributions(_controller)
        {
          entries:  [],
          settings: [
            ModuleContribution.new(
              label:    "Aliyun Captcha",
              entry_key: "status",
              path:     ->(cid) { "/#{cid}/admin/settings/modules/aliyun_captcha" }
            )
          ],
          metadata: { order: 70 }
        }
      end
    end
  end
end
```

- [ ] **Step 6: Run tests, expect pass**

Run:
```bash
bin/rspec spec/services/feature_modules/aliyun_captcha
```

Expected: 3 examples, 0 failures.

- [ ] **Step 7: Boot Rails to confirm auto-discovery**

Run:
```bash
bin/rails runner 'puts FeatureModules::Module.find_by(key: "aliyun_captcha")&.name'
```

Expected output: `Aliyun Captcha`.

- [ ] **Step 8: Commit**

```bash
git add app/services/feature_modules/aliyun_captcha spec/services/feature_modules/aliyun_captcha
git commit -m "feat(aliyun_captcha): FeatureModule registration and provisioner"
```

---

## Task 7: `Page#aliyun_captcha_enabled?` accessor + writer

**Files:**
- Modify: `app/models/page.rb` (add two methods near the other JSON helpers, lines ~170–190)
- Test: extend `spec/models/page_spec.rb`

- [ ] **Step 1: Write the failing test**

Append to `spec/models/page_spec.rb`:

```ruby
RSpec.describe Page, "#aliyun_captcha_enabled?" do
  let(:page) { create(:page) }

  it "returns false when configuration_json has no aliyun_captcha key" do
    expect(page.aliyun_captcha_enabled?).to eq(false)
  end

  it "returns true when configuration_json[aliyun_captcha][enabled] is true" do
    page.aliyun_captcha_enabled = true
    page.save!(validate: false)
    expect(page.reload.aliyun_captcha_enabled?).to eq(true)
  end

  it "returns false when explicitly disabled" do
    page.aliyun_captcha_enabled = false
    page.save!(validate: false)
    expect(page.reload.aliyun_captcha_enabled?).to eq(false)
  end
end
```

- [ ] **Step 2: Run the test, expect failure**

Run:
```bash
bin/rspec spec/models/page_spec.rb -e "aliyun_captcha_enabled?"
```

Expected: `NoMethodError: undefined method 'aliyun_captcha_enabled?'`.

- [ ] **Step 3: Add accessor + writer to `Page`**

In `app/models/page.rb`, immediately after the existing `def handoff_config` block (around line 180), add:

```ruby
# Per-page Aliyun Captcha toggle. Source of truth lives in
# configuration_json["aliyun_captcha"]["enabled"]; the JS page editor
# round-trips it through this writer.
def aliyun_captcha_enabled?
  configuration_json&.dig("aliyun_captcha", "enabled") == true
end

def aliyun_captcha_enabled=(value)
  config = configuration_json || self.class.send(:default_configuration)
  config["aliyun_captcha"] = { "enabled" => ActiveModel::Type::Boolean.new.cast(value) == true }
  self.configuration_json = config
end
```

- [ ] **Step 4: Run the test, expect pass**

Run:
```bash
bin/rspec spec/models/page_spec.rb -e "aliyun_captcha_enabled?"
```

Expected: 3 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/models/page.rb spec/models/page_spec.rb
git commit -m "feat(aliyun_captcha): Page#aliyun_captcha_enabled? accessor and writer"
```

---

## Task 8: `AliyunCaptchaProtectable` controller concern

**Files:**
- Create: `app/controllers/concerns/aliyun_captcha_protectable.rb`
- Test: `spec/concerns/aliyun_captcha_protectable_spec.rb`

- [ ] **Step 1: Write the failing test**

`spec/concerns/aliyun_captcha_protectable_spec.rb`:

```ruby
# frozen_string_literal: true
require "rails_helper"

RSpec.describe AliyunCaptchaProtectable, type: :controller do
  controller(ApplicationController) do
    include AliyunCaptchaProtectable
    before_action :verify_aliyun_captcha!, only: :submit
    def submit
      head :ok
    end

    public :verify_aliyun_captcha!, :captcha_required_for_request?

    attr_accessor :page_for_test, :customer_id_for_test
    def captcha_required_for_request?
      page_for_test&.aliyun_captcha_enabled? &&
        FeatureModules::CustomerAssignment.joins(:feature_module)
          .where(customer_id: customer_id_for_test, feature_modules: { key: "aliyun_captcha" })
          .where.not(status: :suspended).exists?
    end
  end

  before do
    routes.draw { post "submit" => "anonymous#submit" }
    allow_any_instance_of(controller.class).to receive(:current_customer_id).and_return(81721200)
  end

  let(:customer)         { create(:customer, id: 81721200) }
  let(:fm)               { FeatureModules::Module.find_or_create_by!(key: "aliyun_captcha", name: "Aliyun Captcha") }
  let!(:assignment)      { FeatureModules::CustomerAssignment.create!(customer: customer, feature_module: fm, status: :active, configuration: "{}") }
  let(:page)             { instance_double(Page, aliyun_captcha_enabled?: true) }

  before do
    allow_any_instance_of(controller.class).to receive(:instance_variable_get).with(:@page).and_return(page)
    controller.page_for_test         = page
    controller.customer_id_for_test  = customer.id
  end

  context "when activity returns :success" do
    before { allow(AliyunCaptcha::Activities::Verify).to receive(:call).and_return(double(outcome: :success)) }
    it "permits the request" do
      post :submit
      expect(response).to have_http_status(:ok)
    end
  end

  context "when activity returns :invalid" do
    before { allow(AliyunCaptcha::Activities::Verify).to receive(:call).and_return(double(outcome: :invalid)) }
    it "renders 422 with a flash alert" do
      post :submit
      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash.now[:alert]).to be_present
    end
  end

  %i[unreachable configuration_error disabled].each do |outcome|
    context "when activity returns :#{outcome} (fail-open)" do
      before { allow(AliyunCaptcha::Activities::Verify).to receive(:call).and_return(double(outcome: outcome)) }
      it "permits the request and logs a warning" do
        expect(Rails.logger).to receive(:warn).with(/aliyun_captcha.*#{outcome}/)
        post :submit
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
```

- [ ] **Step 2: Run the test, expect failure**

Run:
```bash
bin/rspec spec/concerns/aliyun_captcha_protectable_spec.rb
```

Expected: `NameError: uninitialized constant AliyunCaptchaProtectable`.

- [ ] **Step 3: Implement concern**

`app/controllers/concerns/aliyun_captcha_protectable.rb`:

```ruby
# frozen_string_literal: true

# Adds a `verify_aliyun_captcha!` before-action.
#
# Caller responsibilities:
#   - Set @page (the Page being submitted) before this filter runs.
#   - Provide `current_customer_id`.
#   - Render :show or equivalent when @captcha_failed becomes true.
module AliyunCaptchaProtectable
  extend ActiveSupport::Concern

  private

  def verify_aliyun_captcha!
    return unless captcha_required_for_request?

    result = AliyunCaptcha::Activities::Verify.call(
      verify_param: params[:aliyun_captcha_verify_param].to_s
    )

    case result.outcome
    when :success
      # let the request through
    when :unreachable, :configuration_error, :disabled
      Rails.logger.warn("[aliyun_captcha] fail-open: #{result.outcome}")
    when :invalid
      flash.now[:alert] = I18n.t("aliyun_captcha.errors.invalid")
      @captcha_failed = true
      render :show, status: :unprocessable_entity
    end
  end

  def captcha_required_for_request?
    return false unless @page&.respond_to?(:aliyun_captcha_enabled?)
    return false unless @page.aliyun_captcha_enabled?

    FeatureModules::CustomerAssignment
      .joins(:feature_module)
      .where(customer_id: current_customer_id, feature_modules: { key: "aliyun_captcha" })
      .where.not(status: FeatureModules::CustomerAssignment.statuses[:suspended])
      .exists?
  end
end
```

- [ ] **Step 4: Run the test, expect pass**

Run:
```bash
bin/rspec spec/concerns/aliyun_captcha_protectable_spec.rb
```

Expected: 5 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/concerns/aliyun_captcha_protectable.rb spec/concerns/aliyun_captcha_protectable_spec.rb
git commit -m "feat(aliyun_captcha): controller concern with fail-open policy"
```

---

## Task 9: Wire the concern into `PublicPagesController`

**Files:**
- Modify: `app/controllers/public_pages_controller.rb`
- Test: `spec/requests/public_pages_aliyun_captcha_spec.rb`

- [ ] **Step 1: Write the failing request spec**

`spec/requests/public_pages_aliyun_captcha_spec.rb`:

```ruby
# frozen_string_literal: true
require "rails_helper"

RSpec.describe "Public page captcha protection", type: :request do
  let(:customer) { create(:customer) }
  let!(:entity)  { create(:entity, :with_one_text_field, customer: customer) }
  let(:page) do
    p = create(:page, customer: customer, published: true)
    p.entity_id = entity.id
    p.aliyun_captcha_enabled = true
    p.save!(validate: false)
    p
  end
  let!(:fm)       { FeatureModules::Module.find_or_create_by!(key: "aliyun_captcha", name: "Aliyun Captcha") }
  let!(:assign)   { FeatureModules::CustomerAssignment.create!(customer: customer, feature_module: fm, status: :active, configuration: "{}") }
  let!(:settings) { create(:aliyun_captcha_platform_settings) }

  def submit(verify_param:)
    post "/#{customer.id}/forms/#{page.public_token}",
         params: { aliyun_captcha_verify_param: verify_param, entity.property_schema_json.first["name_slug"] => "hi" }
  end

  context "module on, page on, valid token" do
    before { allow(AliyunCaptcha::Adapters::Aliyun).to receive(:new).and_return(double(verify: { outcome: :success, http_status: 200, raw: {} })) }
    it "creates an EntityEntry" do
      expect { submit(verify_param: "valid-token") }.to change(EntityEntry, :count).by(1)
    end
  end

  context "module on, page on, invalid token" do
    before { allow(AliyunCaptcha::Adapters::Aliyun).to receive(:new).and_return(double(verify: { outcome: :invalid, http_status: 200, raw: {} })) }
    it "renders 422 and creates no entry" do
      expect { submit(verify_param: "bad") }.not_to change(EntityEntry, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  context "module on, page on, Aliyun unreachable" do
    before { allow(AliyunCaptcha::Adapters::Aliyun).to receive(:new).and_return(double(verify: { outcome: :unreachable, http_status: nil, raw: nil })) }
    it "lets the submit through (fail-open)" do
      expect { submit(verify_param: "x") }.to change(EntityEntry, :count).by(1)
    end
  end

  context "module on, page off" do
    before do
      page.aliyun_captcha_enabled = false
      page.save!(validate: false)
    end
    it "skips verification entirely" do
      expect(AliyunCaptcha::Activities::Verify).not_to receive(:call)
      expect { submit(verify_param: "") }.to change(EntityEntry, :count).by(1)
    end
  end

  context "module off for the customer" do
    before { assign.update!(status: :suspended) }
    it "skips verification entirely" do
      expect(AliyunCaptcha::Activities::Verify).not_to receive(:call)
      expect { submit(verify_param: "") }.to change(EntityEntry, :count).by(1)
    end
  end

  context "platform credentials missing" do
    before { settings.update!(access_key_id: nil, access_key_secret: nil, scene_id: nil) }
    it "lets the submit through (fail-open)" do
      expect { submit(verify_param: "") }.to change(EntityEntry, :count).by(1)
    end
  end
end
```

If `entity` factory does not have `:with_one_text_field` trait, replace with the project's existing minimal-entity factory and a single text-field setup helper that lives in `spec/support/`. (Inspect `spec/factories/entity.rb` first.)

- [ ] **Step 2: Run the test, expect failure**

Run:
```bash
bin/rspec spec/requests/public_pages_aliyun_captcha_spec.rb
```

Expected: failures because the captcha filter is not yet wired.

- [ ] **Step 3: Modify `PublicPagesController`**

In `app/controllers/public_pages_controller.rb`, add immediately after the existing `before_action :find_published_page` line (line 13):

```ruby
include AliyunCaptchaProtectable
before_action :verify_aliyun_captcha!, only: :submit
```

- [ ] **Step 4: Run the test, expect pass**

Run:
```bash
bin/rspec spec/requests/public_pages_aliyun_captcha_spec.rb
```

Expected: 6 examples, 0 failures.

- [ ] **Step 5: Run the existing public_pages spec to check for regressions**

Run:
```bash
bin/rspec spec/controllers/public_pages_controller_spec.rb spec/requests/public_pages_*.rb
```

Expected: no new failures versus baseline. If a baseline test posts without `aliyun_captcha_verify_param`, it will still pass because the captcha module is disabled by default for new customers — the test's customer won't have the assignment.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/public_pages_controller.rb spec/requests/public_pages_aliyun_captcha_spec.rb
git commit -m "feat(aliyun_captcha): wire verify_aliyun_captcha! into PublicPagesController#submit"
```

---

## Task 10: i18n locale files

**Files:**
- Create: `config/locales/aliyun_captcha.en.yml`
- Create: `config/locales/aliyun_captcha.zh-CN.yml`

- [ ] **Step 1: Create English locale file**

```yaml
# config/locales/aliyun_captcha.en.yml
en:
  aliyun_captcha:
    page_editor:
      label: "Require Aliyun Captcha"
      hint:  "Show a captcha challenge above the submit button. Helps block bots and abuse on this form."
    widget:
      loading: "Loading verification..."
      submit_disabled_hint: "Complete the verification to enable submit."
    errors:
      invalid:       "Verification failed. Please try again."
      unreachable:   "Verification service is temporarily unavailable. Your submission was accepted."
      configuration: "Verification service is misconfigured. Contact your administrator."
    platform_settings:
      title:             "Aliyun Captcha — Platform Settings"
      access_key_id:     "Access Key ID"
      access_key_secret: "Access Key Secret"
      scene_id:          "Scene ID"
      endpoint:          "Endpoint"
      region:            "Region"
      enabled:           "Enabled platform-wide"
      save:              "Save"
      cancel:            "Cancel"
      health:
        ok:                  "Last verification: OK"
        configuration_error: "Last verification: 4xx — check credentials"
        unreachable:         "Last verification: unreachable"
        unknown:             "No verification recorded yet"
    customer_status:
      title:               "Aliyun Captcha"
      module_disabled:     "This module is disabled. Enable it under Maintenance → Modules to use it."
      credentials_missing: "Aliyun Captcha credentials are not configured by the platform owner."
      pages_using:
        zero:  "No pages are using captcha yet."
        one:   "1 page has captcha enabled."
        other: "%{count} pages have captcha enabled."
```

- [ ] **Step 2: Create Chinese locale file**

```yaml
# config/locales/aliyun_captcha.zh-CN.yml
zh-CN:
  aliyun_captcha:
    page_editor:
      label: "启用阿里云验证码"
      hint:  "在提交按钮上方显示验证码,帮助阻止机器人和滥用提交。"
    widget:
      loading: "正在加载验证..."
      submit_disabled_hint: "请先完成验证以启用提交按钮。"
    errors:
      invalid:       "验证失败,请重试。"
      unreachable:   "验证服务暂时不可用,您的提交已被接受。"
      configuration: "验证服务未正确配置,请联系管理员。"
    platform_settings:
      title:             "阿里云验证码 — 平台设置"
      access_key_id:     "Access Key ID"
      access_key_secret: "Access Key Secret"
      scene_id:          "场景 ID"
      endpoint:          "接入点"
      region:            "区域"
      enabled:           "全平台启用"
      save:              "保存"
      cancel:            "取消"
      health:
        ok:                  "最近一次验证:成功"
        configuration_error: "最近一次验证:4xx — 请检查凭据"
        unreachable:         "最近一次验证:无法访问"
        unknown:             "尚无验证记录"
    customer_status:
      title:               "阿里云验证码"
      module_disabled:     "此模块已禁用。请在 维护 → 模块 中启用后使用。"
      credentials_missing: "平台管理员尚未配置阿里云验证码凭据。"
      pages_using:
        zero:  "尚无页面启用验证码。"
        one:   "已有 1 个页面启用验证码。"
        other: "已有 %{count} 个页面启用验证码。"
```

- [ ] **Step 3: Smoke-test the locale loads**

Run:
```bash
bin/rails runner 'I18n.locale = :"zh-CN"; puts I18n.t("aliyun_captcha.errors.invalid")'
```

Expected output: `验证失败,请重试。`.

- [ ] **Step 4: Commit**

```bash
git add config/locales/aliyun_captcha.en.yml config/locales/aliyun_captcha.zh-CN.yml
git commit -m "feat(aliyun_captcha): English and zh-CN locale strings"
```

---

## Task 11: `WidgetComponent` — public form widget

**Files:**
- Create: `app/components/aliyun_captcha/widget_component.rb`
- Create: `app/components/aliyun_captcha/widget_component.html.erb`
- Test: `spec/components/aliyun_captcha/widget_component_spec.rb`

- [ ] **Step 1: Write the failing test**

`spec/components/aliyun_captcha/widget_component_spec.rb`:

```ruby
# frozen_string_literal: true
require "rails_helper"

RSpec.describe AliyunCaptcha::WidgetComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:page) do
    p = build_stubbed(:page, customer_id: customer.id)
    allow(p).to receive(:aliyun_captcha_enabled?).and_return(true)
    p
  end
  let!(:fm)       { FeatureModules::Module.find_or_create_by!(key: "aliyun_captcha", name: "Aliyun Captcha") }
  let!(:assign)   { FeatureModules::CustomerAssignment.create!(customer: customer, feature_module: fm, status: :active, configuration: "{}") }
  let!(:settings) { create(:aliyun_captcha_platform_settings) }

  def render_for(p, customer_id: customer.id)
    render_inline(described_class.new(page: p, customer_id: customer_id))
  end

  it "renders the mount point and hidden input when module on, page on, credentials configured" do
    output = render_for(page)
    expect(output.css("[data-controller='aliyun-captcha']")).to be_present
    expect(output.css("[data-aliyun-captcha-target='mount']")).to be_present
    expect(output.css("input[type='hidden'][name='aliyun_captcha_verify_param']")).to be_present
  end

  it "renders nothing when the page toggle is off" do
    allow(page).to receive(:aliyun_captcha_enabled?).and_return(false)
    expect(render_for(page).to_html.strip).to be_blank
  end

  it "renders nothing when the customer has not enabled the module" do
    assign.update!(status: :suspended)
    expect(render_for(page).to_html.strip).to be_blank
  end

  it "renders nothing when platform credentials are missing" do
    settings.update!(access_key_id: nil, access_key_secret: nil, scene_id: nil)
    expect(render_for(page).to_html.strip).to be_blank
  end

  it "passes the current locale to the Stimulus controller" do
    I18n.with_locale(:"zh-CN") do
      output = render_for(page)
      expect(output.css("[data-aliyun-captcha-locale-value]").attr("data-aliyun-captcha-locale-value").value).to eq("zh-CN")
    end
  end
end
```

- [ ] **Step 2: Run the test, expect failure**

Run:
```bash
bin/rspec spec/components/aliyun_captcha/widget_component_spec.rb
```

Expected: `NameError: uninitialized constant AliyunCaptcha::WidgetComponent`.

- [ ] **Step 3: Implement component**

`app/components/aliyun_captcha/widget_component.rb`:

```ruby
# frozen_string_literal: true

module AliyunCaptcha
  class WidgetComponent < ViewComponent::Base
    def initialize(page:, customer_id:)
      @page        = page
      @customer_id = customer_id
    end

    def render?
      @page&.aliyun_captcha_enabled? && module_enabled? && settings.configured?
    end

    def scene_id = settings.scene_id
    def locale   = I18n.locale.to_s

    private

    def settings
      @settings ||= AliyunCaptcha::PlatformSettings.instance
    end

    def module_enabled?
      FeatureModules::CustomerAssignment
        .joins(:feature_module)
        .where(customer_id: @customer_id, feature_modules: { key: "aliyun_captcha" })
        .where.not(status: FeatureModules::CustomerAssignment.statuses[:suspended])
        .exists?
    end
  end
end
```

`app/components/aliyun_captcha/widget_component.html.erb`:

```erb
<div class="my-4"
     data-controller="aliyun-captcha"
     data-aliyun-captcha-scene-id-value="<%= scene_id %>"
     data-aliyun-captcha-locale-value="<%= locale %>">
  <div class="min-h-[44px]" data-aliyun-captcha-target="mount">
    <p class="text-sm text-gray-500"><%= t("aliyun_captcha.widget.loading") %></p>
  </div>
  <input type="hidden" name="aliyun_captcha_verify_param" value="" data-aliyun-captcha-target="input">
  <p class="text-xs text-gray-400 mt-1"><%= t("aliyun_captcha.widget.submit_disabled_hint") %></p>
</div>
```

- [ ] **Step 4: Run the test, expect pass**

Run:
```bash
bin/rspec spec/components/aliyun_captcha/widget_component_spec.rb
```

Expected: 5 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/components/aliyun_captcha/widget_component.rb app/components/aliyun_captcha/widget_component.html.erb spec/components/aliyun_captcha/widget_component_spec.rb
git commit -m "feat(aliyun_captcha): WidgetComponent for public-form rendering"
```

---

## Task 12: Stimulus controller — `aliyun_captcha_controller.js`

**Files:**
- Create: `app/javascript/controllers/aliyun_captcha_controller.js`

- [ ] **Step 1: Implement Stimulus controller**

```javascript
// app/javascript/controllers/aliyun_captcha_controller.js
import { Controller } from "@hotwired/stimulus"

const SDK_URL = "https://o.alicdn.com/captcha-frontend/aliyunCaptcha/AliyunCaptcha.js"

let sdkPromise = null

function loadSdk() {
  if (window.AliyunCaptcha) return Promise.resolve(window.AliyunCaptcha)
  if (sdkPromise) return sdkPromise
  sdkPromise = new Promise((resolve, reject) => {
    const script = document.createElement("script")
    script.src = SDK_URL
    script.async = true
    script.onload = () => resolve(window.AliyunCaptcha)
    script.onerror = () => reject(new Error("Failed to load Aliyun Captcha SDK"))
    document.head.appendChild(script)
  })
  return sdkPromise
}

function mapLocale(rails) {
  return rails && rails.toLowerCase().startsWith("zh") ? "cn" : "en"
}

export default class extends Controller {
  static targets = ["mount", "input"]
  static values  = { sceneId: String, locale: String }

  connect() {
    loadSdk().then(() => this.render()).catch(err => console.warn("[aliyun_captcha]", err))
  }

  render() {
    if (!window.AliyunCaptcha || !this.hasMountTarget) return

    const form = this.element.closest("form")
    const submit = form && form.querySelector("button[type='submit'], input[type='submit']")
    if (submit) submit.disabled = true

    window.AliyunCaptcha.init({
      SceneId:               this.sceneIdValue,
      mode:                  "embed",
      element:               this.mountTarget,
      language:              mapLocale(this.localeValue),
      captchaVerifyCallback: (param) => this.onVerify(param, submit),
      onBizResultCallback:   () => {}
    })
  }

  onVerify(verifyParam, submit) {
    if (this.hasInputTarget) this.inputTarget.value = verifyParam || ""
    if (submit) submit.disabled = false
    return Promise.resolve({ captchaResult: true, bizResult: true })
  }
}
```

- [ ] **Step 2: Smoke-test that the asset compiles**

Run:
```bash
rm -f public/assets/.manifest.json && bin/rails assets:precompile 2>&1 | tail -20
```

Expected: no JS syntax errors. Roll back the precompile artifacts if you don't want them in the working tree (`bin/rails assets:clobber` is fine).

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/aliyun_captcha_controller.js
git commit -m "feat(aliyun_captcha): Stimulus controller wiring Aliyun JS SDK"
```

---

## Task 13: `PageEditorToggleComponent` — page-editor switch

**Files:**
- Create: `app/components/aliyun_captcha/page_editor_toggle_component.rb`
- Create: `app/components/aliyun_captcha/page_editor_toggle_component.html.erb`
- Test: `spec/components/aliyun_captcha/page_editor_toggle_component_spec.rb`
- Modify: `app/views/admin/maintenance/pages/_editor.html.erb` (insert near line 610 — start of form_settings section)

- [ ] **Step 1: Write the failing test**

`spec/components/aliyun_captcha/page_editor_toggle_component_spec.rb`:

```ruby
# frozen_string_literal: true
require "rails_helper"

RSpec.describe AliyunCaptcha::PageEditorToggleComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:page)     { build_stubbed(:page, customer_id: customer.id) }
  let!(:fm)      { FeatureModules::Module.find_or_create_by!(key: "aliyun_captcha", name: "Aliyun Captcha") }

  it "renders nothing when the customer has not enabled the module" do
    output = render_inline(described_class.new(page: page, customer_id: customer.id))
    expect(output.to_html.strip).to be_blank
  end

  it "renders the toggle reflecting the current state when the customer has enabled the module" do
    FeatureModules::CustomerAssignment.create!(customer: customer, feature_module: fm, status: :active, configuration: "{}")
    allow(page).to receive(:aliyun_captcha_enabled?).and_return(true)
    output = render_inline(described_class.new(page: page, customer_id: customer.id))
    expect(output.css("input[type='checkbox'][name='page[aliyun_captcha_enabled]']")).to be_present
    expect(output.css("input[type='checkbox'][name='page[aliyun_captcha_enabled]'][checked]")).to be_present
  end
end
```

- [ ] **Step 2: Run the test, expect failure**

Run:
```bash
bin/rspec spec/components/aliyun_captcha/page_editor_toggle_component_spec.rb
```

Expected: `NameError: uninitialized constant AliyunCaptcha::PageEditorToggleComponent`.

- [ ] **Step 3: Implement component**

`app/components/aliyun_captcha/page_editor_toggle_component.rb`:

```ruby
# frozen_string_literal: true

module AliyunCaptcha
  class PageEditorToggleComponent < ViewComponent::Base
    def initialize(page:, customer_id:)
      @page        = page
      @customer_id = customer_id
    end

    def render?
      FeatureModules::CustomerAssignment
        .joins(:feature_module)
        .where(customer_id: @customer_id, feature_modules: { key: "aliyun_captcha" })
        .where.not(status: FeatureModules::CustomerAssignment.statuses[:suspended])
        .exists?
    end

    def checked? = @page.aliyun_captcha_enabled?
  end
end
```

`app/components/aliyun_captcha/page_editor_toggle_component.html.erb`:

```erb
<div class="mt-4 border rounded-md p-3 bg-white">
  <label class="inline-flex items-center gap-2">
    <input type="hidden" name="page[aliyun_captcha_enabled]" value="0">
    <input type="checkbox" name="page[aliyun_captcha_enabled]" value="1"
           class="rounded border-gray-300"
           <%= "checked" if checked? %>>
    <span class="text-sm font-medium text-gray-800"><%= t("aliyun_captcha.page_editor.label") %></span>
  </label>
  <p class="text-xs text-gray-500 mt-1"><%= t("aliyun_captcha.page_editor.hint") %></p>
</div>
```

- [ ] **Step 4: Permit the param in the pages controller**

Inspect `app/controllers/admin/maintenance/pages_controller.rb` (around the strong-params block — search for `params.require(:page)`). Add `:aliyun_captcha_enabled` to the permitted params:

```ruby
params.require(:page).permit(
  # ... existing keys ...
  :aliyun_captcha_enabled
)
```

(If the existing structure is `permit(...).tap { ... }` or uses a separate method, add the key in the same place; do not duplicate it.)

- [ ] **Step 5: Insert the toggle into the page editor view**

Open `app/views/admin/maintenance/pages/_editor.html.erb` and find the line near 610:

```erb
<% form_settings = @page.configuration_json&.dig("form_settings") || {} %>
```

Immediately above that line, insert:

```erb
<%= render(AliyunCaptcha::PageEditorToggleComponent.new(page: @page, customer_id: current_customer_id)) %>
```

- [ ] **Step 6: Run the test, expect pass**

Run:
```bash
bin/rspec spec/components/aliyun_captcha/page_editor_toggle_component_spec.rb
```

Expected: 2 examples, 0 failures.

- [ ] **Step 7: Smoke-test the editor renders**

Run:
```bash
rm -f public/assets/.manifest.json
bin/rails server -b 0.0.0.0 -p 3000 &
sleep 5
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3000/up"
kill %1 2>/dev/null
```

Expected: `200`. (Server boots without errors. Visual verification of the editor UI is performed in Task 17.)

- [ ] **Step 8: Commit**

```bash
git add app/components/aliyun_captcha/page_editor_toggle_component.rb app/components/aliyun_captcha/page_editor_toggle_component.html.erb spec/components/aliyun_captcha/page_editor_toggle_component_spec.rb app/views/admin/maintenance/pages/_editor.html.erb app/controllers/admin/maintenance/pages_controller.rb
git commit -m "feat(aliyun_captcha): page editor toggle component and permitted param"
```

---

## Task 14: Render `WidgetComponent` on the public page above the submit button

**Files:**
- Modify: the template that renders the public form's submit button

- [ ] **Step 1: Locate the submit button**

Run:
```bash
grep -rn 'type="submit"\|type=:submit\|submit_tag\|button_to' app/services/page_content_generator app/views/public_pages 2>/dev/null
```

The public page content is generated by `PageContentGenerator`. Read `app/services/page_content_generator.rb` and any partials it composes; find where the submit button is emitted.

- [ ] **Step 2: Insert the widget mount point**

Inside the generator (or template) immediately preceding the submit button, render:

```erb
<%= render(AliyunCaptcha::WidgetComponent.new(page: @page, customer_id: current_customer_id)) %>
```

If the surrounding code is a Ruby string-builder (not ERB), use:

```ruby
output << ApplicationController.render(
  AliyunCaptcha::WidgetComponent.new(page: @page, customer_id: @customer_id)
)
```

Do not add custom CSS — the component already uses Tailwind classes.

- [ ] **Step 3: Manually verify via browser**

Run:
```bash
rm -f public/assets/.manifest.json && bin/rails server -b 0.0.0.0 -p 3000
```

Then in a browser:
1. Visit `/<platform-owner-cid>/admin/maintenance/platform/aliyun_captcha` (will exist after Task 15) — for now, seed `AliyunCaptcha::PlatformSettings.instance.update!(access_key_id: "test", access_key_secret: "test", scene_id: "test")` from `bin/rails console`.
2. Enable the `aliyun_captcha` module for a test customer (`FeatureModules::CustomerAssignment.create!(...)`).
3. Toggle a published page on (in the page editor or set `page.aliyun_captcha_enabled = true; page.save!(validate: false)`).
4. Visit `/<cid>/forms/<token>`.
5. Confirm: the loading text appears above the submit button; the submit button is initially disabled; the Stimulus controller injects the SDK script tag (verify in DevTools Network tab — it will fail to load the actual widget without real credentials, which is fine for this smoke test).

Document any visual issue and fix before moving on.

- [ ] **Step 4: Commit**

```bash
git add app/services/page_content_generator
git commit -m "feat(aliyun_captcha): render WidgetComponent above public-form submit button"
```

---

## Task 15: Platform settings UI — controller, contract, activity, view, component

**Files:**
- Create: `app/services/aliyun_captcha/contracts/platform_settings.rb`
- Create: `app/services/aliyun_captcha/activities/update_platform_settings.rb`
- Create: `app/controllers/admin/maintenance/platform/aliyun_captcha/settings_controller.rb`
- Create: `app/components/admin/maintenance/platform/aliyun_captcha/settings_component.rb`
- Create: `app/components/admin/maintenance/platform/aliyun_captcha/settings_component.html.erb`
- Create: `app/views/admin/maintenance/platform/aliyun_captcha/settings/show.html.erb`
- Create: `app/views/admin/maintenance/platform/aliyun_captcha/settings/edit.html.erb`
- Modify: `config/routes.rb`
- Test: `spec/services/aliyun_captcha/activities/update_platform_settings_spec.rb`
- Test: `spec/controllers/admin/maintenance/platform/aliyun_captcha/settings_controller_spec.rb`

- [ ] **Step 1: Write the failing activity test**

`spec/services/aliyun_captcha/activities/update_platform_settings_spec.rb`:

```ruby
# frozen_string_literal: true
require "rails_helper"

RSpec.describe AliyunCaptcha::Activities::UpdatePlatformSettings do
  let!(:settings) { create(:aliyun_captcha_platform_settings, access_key_secret: "OLD_SECRET") }

  it "validates required fields" do
    res = described_class.call(params: { access_key_id: "", scene_id: "", access_key_secret: "" })
    expect(res.success?).to eq(false)
    expect(res.errors).to include(match(/access_key_id/i))
    expect(res.errors).to include(match(/scene_id/i))
  end

  it "updates non-secret fields and rotates the secret on non-blank submission" do
    res = described_class.call(params: {
      access_key_id: "NEW_KEY", scene_id: "scn-2", access_key_secret: "NEW_SECRET",
      endpoint: "captcha.cn-shanghai.aliyuncs.com", region: "cn-shanghai", enabled: "1"
    })
    expect(res.success?).to eq(true)
    expect(settings.reload.access_key_id).to eq("NEW_KEY")
    expect(settings.reload.access_key_secret).to eq("NEW_SECRET")
    expect(settings.reload.enabled).to eq(true)
  end

  it "preserves the existing secret when access_key_secret is blank" do
    described_class.call(params: {
      access_key_id: "NEW_KEY", scene_id: "scn-2", access_key_secret: "",
      endpoint: "captcha.cn-shanghai.aliyuncs.com", region: "cn-shanghai"
    })
    expect(settings.reload.access_key_secret).to eq("OLD_SECRET")
  end
end
```

- [ ] **Step 2: Implement contract**

`app/services/aliyun_captcha/contracts/platform_settings.rb`:

```ruby
# frozen_string_literal: true

require "reform"
require "reform/form/dry"

module AliyunCaptcha
  module Contracts
    class PlatformSettings < Reform::Form
      property :access_key_id
      property :access_key_secret
      property :scene_id
      property :endpoint
      property :region
      property :enabled

      validates :access_key_id, presence: true
      validates :scene_id,      presence: true
      validates :endpoint,      presence: true
      validates :region,        presence: true
    end
  end
end
```

- [ ] **Step 3: Implement activity**

`app/services/aliyun_captcha/activities/update_platform_settings.rb`:

```ruby
# frozen_string_literal: true

module AliyunCaptcha
  module Activities
    class UpdatePlatformSettings
      Result = Struct.new(:success?, :model, :errors, keyword_init: true)

      def self.call(params:)
        settings = AliyunCaptcha::PlatformSettings.instance
        merged   = sanitize(params, settings)
        contract = AliyunCaptcha::Contracts::PlatformSettings.new(settings)

        if contract.validate(merged) && settings.update(merged)
          Result.new(success?: true, model: settings, errors: [])
        else
          errors = contract.errors.full_messages + settings.errors.full_messages
          Result.new(success?: false, model: settings, errors: errors.uniq)
        end
      end

      def self.sanitize(params, settings)
        h = params.to_h.symbolize_keys
        h[:enabled] = ActiveModel::Type::Boolean.new.cast(h[:enabled])
        # Masked-field-preservation: blank submission keeps the existing secret.
        if h[:access_key_secret].blank?
          h[:access_key_secret] = settings.access_key_secret
        end
        h
      end
    end
  end
end
```

- [ ] **Step 4: Run the activity test, expect pass**

Run:
```bash
bin/rspec spec/services/aliyun_captcha/activities/update_platform_settings_spec.rb
```

Expected: 3 examples, 0 failures.

- [ ] **Step 5: Add routes**

In `config/routes.rb`, inside the `scope "platform", as: :platform do` block (around line 215), and the existing `scope :module_settings, as: :module_settings do` (line 230), add:

```ruby
namespace :aliyun_captcha, module: "maintenance/platform/aliyun_captcha" do
  resource :settings, only: %i[show edit update]
end
```

So the section reads:

```ruby
scope :module_settings, as: :module_settings do
  namespace :sms, module: "maintenance/platform/sms" do
    resources :credentials, only: %i[index new create edit update]
    resources :templates,   only: %i[index new create edit update destroy]
  end
  namespace :aliyun_captcha, module: "maintenance/platform/aliyun_captcha" do
    resource :settings, only: %i[show edit update]
  end
end
```

Then, **outside** the `:platform` scope, inside the `namespace :admin do` block (search for the existing `namespace :settings do` near line 125), add:

```ruby
namespace :modules do
  # ... existing ...
  namespace :aliyun_captcha, module: "settings/modules/aliyun_captcha" do
    resource :status, only: :show
  end
end
```

So the reflective view is:

```ruby
namespace :settings do
  namespace :modules do
    namespace :payments do
      resources :merchant_accounts, only: %i[index new create edit update]
    end
    namespace :authentication do
      # existing
    end
    namespace :aliyun_captcha, module: "settings/modules/aliyun_captcha" do
      resource :status, only: :show
    end
  end
end
```

- [ ] **Step 6: Verify routes load**

Run:
```bash
bin/rails routes | grep aliyun_captcha
```

Expected lines (paths may have trailing slashes):

```
GET    /:customer_id/admin/maintenance/platform/module_settings/aliyun_captcha/settings(.:format)       admin/maintenance/platform/aliyun_captcha/settings#show
GET    /:customer_id/admin/maintenance/platform/module_settings/aliyun_captcha/settings/edit(.:format)  admin/maintenance/platform/aliyun_captcha/settings#edit
PATCH  /:customer_id/admin/maintenance/platform/module_settings/aliyun_captcha/settings(.:format)       admin/maintenance/platform/aliyun_captcha/settings#update
GET    /:customer_id/admin/settings/modules/aliyun_captcha/status(.:format)                             admin/settings/modules/aliyun_captcha/status#show
```

- [ ] **Step 7: Write the failing controller test**

`spec/controllers/admin/maintenance/platform/aliyun_captcha/settings_controller_spec.rb`:

```ruby
# frozen_string_literal: true
require "rails_helper"

RSpec.describe Admin::Maintenance::Platform::AliyunCaptcha::SettingsController, type: :controller do
  render_views
  let(:platform_owner_cid) { 81721200 }
  let!(:platform_owner)    { create(:customer, id: platform_owner_cid) }
  let!(:other_customer)    { create(:customer) }
  let(:owner_user)         { create(:user, :owner, customer: platform_owner) }
  let(:non_owner)          { create(:user, :admin, customer: other_customer) }

  before do
    AliyunCaptcha::PlatformSettings.instance   # ensure row exists
  end

  describe "GET #show" do
    it "is allowed for platform owner" do
      sign_in owner_user
      get :show, params: { customer_id: platform_owner.id }
      expect(response).to have_http_status(:ok)
    end

    it "is forbidden for non-owners" do
      sign_in non_owner
      get :show, params: { customer_id: other_customer.id }
      expect(response).to have_http_status(:forbidden).or have_http_status(:not_found).or have_http_status(:redirect)
    end
  end

  describe "PATCH #update" do
    it "rotates credentials on a non-blank secret submission" do
      sign_in owner_user
      patch :update, params: {
        customer_id: platform_owner.id,
        aliyun_captcha_platform_settings: {
          access_key_id: "AK", access_key_secret: "S2", scene_id: "scn",
          endpoint: "captcha.cn-shanghai.aliyuncs.com", region: "cn-shanghai", enabled: "1"
        }
      }
      expect(AliyunCaptcha::PlatformSettings.instance.access_key_secret).to eq("S2")
    end

    it "preserves the secret on blank submission" do
      AliyunCaptcha::PlatformSettings.instance.update!(access_key_id: "AK", access_key_secret: "OLD", scene_id: "scn")
      sign_in owner_user
      patch :update, params: {
        customer_id: platform_owner.id,
        aliyun_captcha_platform_settings: {
          access_key_id: "AK2", access_key_secret: "", scene_id: "scn",
          endpoint: "captcha.cn-shanghai.aliyuncs.com", region: "cn-shanghai"
        }
      }
      expect(AliyunCaptcha::PlatformSettings.instance.access_key_secret).to eq("OLD")
    end
  end
end
```

If `:owner` / `:admin` user traits are named differently, adjust to whatever already exists in `spec/factories/users.rb`. (Look at how `Admin::Maintenance::Platform::Sms::CredentialsController` specs do it — mirror exactly.)

- [ ] **Step 8: Implement controller**

`app/controllers/admin/maintenance/platform/aliyun_captcha/settings_controller.rb`:

```ruby
# frozen_string_literal: true

module Admin
module Maintenance
module Platform
  module AliyunCaptcha
    # Platform-owner CRUD for Aliyun Captcha credentials.
    # Lives under /:cid/admin/maintenance/platform/module_settings/aliyun_captcha/settings.
    class SettingsController < ApplicationController
      set_tenant_from_route_params required: true

      before_action :authenticate_user!
      before_action :require_platform_owner!
      before_action :set_settings

      def show
      end

      def edit
      end

      def update
        result = ::AliyunCaptcha::Activities::UpdatePlatformSettings.call(params: settings_params)
        if result.success?
          redirect_to "/#{current_customer.id}/admin/maintenance/platform/module_settings/aliyun_captcha/settings",
                      notice: I18n.t("aliyun_captcha.platform_settings.title") + " updated."
        else
          @errors = result.errors
          render :edit, status: :unprocessable_entity
        end
      end

      private

      def set_settings
        @settings = ::AliyunCaptcha::PlatformSettings.instance
      end

      def settings_params
        params.require(:aliyun_captcha_platform_settings).permit(
          :access_key_id, :access_key_secret, :scene_id, :endpoint, :region, :enabled
        )
      end
    end
  end
end
end
end
```

- [ ] **Step 9: Implement settings component**

`app/components/admin/maintenance/platform/aliyun_captcha/settings_component.rb`:

```ruby
# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module AliyunCaptcha
        class SettingsComponent < ViewComponent::Base
          def initialize(settings:, mode:, errors: [])
            @settings = settings
            @mode     = mode # :show or :edit
            @errors   = errors
          end

          def health_status_key
            case @settings.last_health_check_status
            when "ok"                  then "ok"
            when "configuration_error" then "configuration_error"
            when "unreachable"         then "unreachable"
            else                            "unknown"
            end
          end

          attr_reader :settings, :mode, :errors
        end
      end
    end
  end
end
```

`app/components/admin/maintenance/platform/aliyun_captcha/settings_component.html.erb`:

```erb
<section class="bg-white shadow rounded-lg p-6 max-w-2xl">
  <h1 class="text-xl font-semibold mb-4"><%= t("aliyun_captcha.platform_settings.title") %></h1>

  <% if errors.any? %>
    <div class="bg-red-50 border border-red-200 text-red-800 rounded p-3 mb-4">
      <ul class="list-disc list-inside text-sm">
        <% errors.each do |msg| %><li><%= msg %></li><% end %>
      </ul>
    </div>
  <% end %>

  <% if mode == :show %>
    <dl class="grid grid-cols-2 gap-y-2 text-sm">
      <dt class="text-gray-500"><%= t("aliyun_captcha.platform_settings.access_key_id") %></dt>
      <dd><%= settings.access_key_id.presence || "—" %></dd>
      <dt class="text-gray-500"><%= t("aliyun_captcha.platform_settings.scene_id") %></dt>
      <dd><%= settings.scene_id.presence || "—" %></dd>
      <dt class="text-gray-500"><%= t("aliyun_captcha.platform_settings.endpoint") %></dt>
      <dd><%= settings.endpoint %></dd>
      <dt class="text-gray-500"><%= t("aliyun_captcha.platform_settings.region") %></dt>
      <dd><%= settings.region %></dd>
      <dt class="text-gray-500"><%= t("aliyun_captcha.platform_settings.enabled") %></dt>
      <dd><%= settings.enabled? ? "✓" : "—" %></dd>
    </dl>
    <div class="mt-4 text-sm">
      <span class="inline-block px-2 py-1 rounded bg-gray-100 text-gray-700">
        <%= t("aliyun_captcha.platform_settings.health.#{health_status_key}") %>
      </span>
    </div>
    <div class="mt-6">
      <%= link_to t("aliyun_captcha.platform_settings.save"),
                  edit_admin_maintenance_platform_module_settings_aliyun_captcha_settings_path,
                  class: "inline-block px-4 py-2 rounded bg-blue-600 text-white hover:bg-blue-700" %>
    </div>
  <% else %>
    <%= form_with url: admin_maintenance_platform_module_settings_aliyun_captcha_settings_path,
                  method: :patch, local: true do |f| %>
      <% %i[access_key_id scene_id endpoint region].each do |field| %>
        <div class="mb-3">
          <label class="block text-sm font-medium mb-1"><%= t("aliyun_captcha.platform_settings.#{field}") %></label>
          <input type="text" name="aliyun_captcha_platform_settings[<%= field %>]"
                 value="<%= settings.public_send(field) %>"
                 class="w-full border rounded px-2 py-1">
        </div>
      <% end %>
      <div class="mb-3">
        <label class="block text-sm font-medium mb-1"><%= t("aliyun_captcha.platform_settings.access_key_secret") %></label>
        <input type="password" name="aliyun_captcha_platform_settings[access_key_secret]"
               placeholder="<%= settings.access_key_secret.present? ? "••••••• (leave blank to keep current)" : "" %>"
               class="w-full border rounded px-2 py-1">
      </div>
      <div class="mb-3">
        <label class="inline-flex items-center gap-2">
          <input type="hidden" name="aliyun_captcha_platform_settings[enabled]" value="0">
          <input type="checkbox" name="aliyun_captcha_platform_settings[enabled]" value="1"
                 <%= "checked" if settings.enabled? %>>
          <span class="text-sm"><%= t("aliyun_captcha.platform_settings.enabled") %></span>
        </label>
      </div>
      <div class="mt-4 flex gap-2">
        <button type="submit" class="px-4 py-2 rounded bg-blue-600 text-white hover:bg-blue-700">
          <%= t("aliyun_captcha.platform_settings.save") %>
        </button>
        <%= link_to t("aliyun_captcha.platform_settings.cancel"),
                    admin_maintenance_platform_module_settings_aliyun_captcha_settings_path,
                    class: "px-4 py-2 rounded border" %>
      </div>
    <% end %>
  <% end %>
</section>
```

- [ ] **Step 10: Implement views**

`app/views/admin/maintenance/platform/aliyun_captcha/settings/show.html.erb`:

```erb
<%= render Admin::Maintenance::Platform::AliyunCaptcha::SettingsComponent.new(settings: @settings, mode: :show) %>
```

`app/views/admin/maintenance/platform/aliyun_captcha/settings/edit.html.erb`:

```erb
<%= render Admin::Maintenance::Platform::AliyunCaptcha::SettingsComponent.new(settings: @settings, mode: :edit, errors: @errors || []) %>
```

- [ ] **Step 11: Run controller test, expect pass**

Run:
```bash
bin/rspec spec/controllers/admin/maintenance/platform/aliyun_captcha/settings_controller_spec.rb
```

Expected: all examples pass. If user-factory traits don't exist, fix the test (not the code) to use whatever the SMS credentials spec uses.

- [ ] **Step 12: Commit**

```bash
git add app/services/aliyun_captcha/contracts/platform_settings.rb \
        app/services/aliyun_captcha/activities/update_platform_settings.rb \
        app/controllers/admin/maintenance/platform/aliyun_captcha \
        app/components/admin/maintenance/platform/aliyun_captcha \
        app/views/admin/maintenance/platform/aliyun_captcha \
        config/routes.rb \
        spec/services/aliyun_captcha/activities/update_platform_settings_spec.rb \
        spec/controllers/admin/maintenance/platform/aliyun_captcha
git commit -m "feat(aliyun_captcha): platform settings controller, contract, activity, and views"
```

---

## Task 16: Customer status page (read-only)

**Files:**
- Create: `app/controllers/admin/settings/modules/aliyun_captcha/status_controller.rb`
- Create: `app/components/admin/settings/modules/aliyun_captcha/status_component.rb`
- Create: `app/components/admin/settings/modules/aliyun_captcha/status_component.html.erb`
- Create: `app/views/admin/settings/modules/aliyun_captcha/status/show.html.erb`
- Test: `spec/controllers/admin/settings/modules/aliyun_captcha/status_controller_spec.rb`

- [ ] **Step 1: Implement controller**

`app/controllers/admin/settings/modules/aliyun_captcha/status_controller.rb`:

```ruby
# frozen_string_literal: true

module Admin
module Settings
module Modules
  module AliyunCaptcha
    class StatusController < ApplicationController
      set_tenant_from_route_params required: true

      before_action :authenticate_user!
      before_action :require_admin_or_owner!

      def show
        @settings = ::AliyunCaptcha::PlatformSettings.instance
        @module_enabled = FeatureModules::CustomerAssignment
                            .joins(:feature_module)
                            .where(customer_id: current_customer_id, feature_modules: { key: "aliyun_captcha" })
                            .where.not(status: FeatureModules::CustomerAssignment.statuses[:suspended])
                            .exists?
        @pages_with_captcha = Page.for_current_customer
                                  .where("configuration LIKE ?", "%\"aliyun_captcha\"%")
                                  .select { |p| p.aliyun_captcha_enabled? }
                                  .count
      end
    end
  end
end
end
end
```

- [ ] **Step 2: Implement component**

`app/components/admin/settings/modules/aliyun_captcha/status_component.rb`:

```ruby
# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module AliyunCaptcha
        class StatusComponent < ViewComponent::Base
          def initialize(settings:, module_enabled:, pages_with_captcha:)
            @settings           = settings
            @module_enabled     = module_enabled
            @pages_with_captcha = pages_with_captcha
          end

          attr_reader :settings, :module_enabled, :pages_with_captcha
        end
      end
    end
  end
end
```

`app/components/admin/settings/modules/aliyun_captcha/status_component.html.erb`:

```erb
<section class="bg-white shadow rounded-lg p-6 max-w-2xl">
  <h1 class="text-xl font-semibold mb-4"><%= t("aliyun_captcha.customer_status.title") %></h1>

  <% unless module_enabled %>
    <div class="bg-yellow-50 border border-yellow-200 text-yellow-800 rounded p-3 mb-3 text-sm">
      <%= t("aliyun_captcha.customer_status.module_disabled") %>
    </div>
  <% end %>

  <% unless settings.configured? %>
    <div class="bg-yellow-50 border border-yellow-200 text-yellow-800 rounded p-3 mb-3 text-sm">
      <%= t("aliyun_captcha.customer_status.credentials_missing") %>
    </div>
  <% end %>

  <p class="text-sm text-gray-700">
    <%= t("aliyun_captcha.customer_status.pages_using", count: pages_with_captcha) %>
  </p>
</section>
```

- [ ] **Step 3: Implement view**

`app/views/admin/settings/modules/aliyun_captcha/status/show.html.erb`:

```erb
<%= render Admin::Settings::Modules::AliyunCaptcha::StatusComponent.new(
      settings:           @settings,
      module_enabled:     @module_enabled,
      pages_with_captcha: @pages_with_captcha
    ) %>
```

- [ ] **Step 4: Write the failing controller test**

`spec/controllers/admin/settings/modules/aliyun_captcha/status_controller_spec.rb`:

```ruby
# frozen_string_literal: true
require "rails_helper"

RSpec.describe Admin::Settings::Modules::AliyunCaptcha::StatusController, type: :controller do
  render_views
  let(:customer)  { create(:customer) }
  let(:admin)     { create(:user, :admin, customer: customer) }
  let(:member)    { create(:user, :member, customer: customer) }

  before { AliyunCaptcha::PlatformSettings.instance }

  it "renders for customer admin" do
    sign_in admin
    get :show, params: { customer_id: customer.id }
    expect(response).to have_http_status(:ok)
  end

  it "rejects non-admin members" do
    sign_in member
    get :show, params: { customer_id: customer.id }
    expect(response.status).to be_in([302, 403, 404])
  end
end
```

- [ ] **Step 5: Run the test, expect pass**

Run:
```bash
bin/rspec spec/controllers/admin/settings/modules/aliyun_captcha/status_controller_spec.rb
```

Expected: 2 examples, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/admin/settings/modules/aliyun_captcha \
        app/components/admin/settings/modules/aliyun_captcha \
        app/views/admin/settings/modules/aliyun_captcha \
        spec/controllers/admin/settings/modules/aliyun_captcha
git commit -m "feat(aliyun_captcha): customer status page (read-only)"
```

---

## Task 17: End-to-end manual smoke test

**Files:** none

- [ ] **Step 1: Boot the server**

Run:
```bash
rm -f public/assets/.manifest.json && bin/rails server -b 0.0.0.0 -p 3000
```

- [ ] **Step 2: Configure platform credentials**

Sign in as platform-owner user (under customer `81721200`). Visit:

```
http://localhost:3000/81721200/admin/maintenance/platform/module_settings/aliyun_captcha/settings/edit
```

Enter test credentials (from your Aliyun console — even sandbox-mode keys are fine), save. Confirm the show page now lists the Access Key ID and shows "No verification recorded yet".

- [ ] **Step 3: Enable the module for a test customer**

Visit:

```
http://localhost:3000/<test-cid>/admin/maintenance/modules
```

Enable the "Aliyun Captcha" module. (If the module doesn't appear, check `bin/rails runner 'puts FeatureModules::Module.find_by(key: "aliyun_captcha")&.attributes'`.)

- [ ] **Step 4: Toggle a page on**

Open a published page in the editor:

```
http://localhost:3000/<test-cid>/admin/maintenance/pages/<id>/edit
```

Confirm the "Require Aliyun Captcha" toggle appears in the form-settings section. Enable it, save.

- [ ] **Step 5: Submit the public form**

Visit:

```
http://localhost:3000/<test-cid>/forms/<token>
```

Confirm:
- The captcha widget loads above the submit button.
- The submit button is initially disabled.
- After verifying, the submit button enables and submission succeeds.
- An `EntityEntry` is created (check `bin/rails console`: `EntityEntry.last`).
- `AliyunCaptcha::PlatformSettings.instance.last_health_check_status` is `"ok"`.

- [ ] **Step 6: Verify fail-open**

In console, simulate Aliyun being down:

```ruby
allow(AliyunCaptcha::Adapters::Aliyun).to receive(:new).and_return(
  Object.new.tap { |o| def o.verify(*); { outcome: :unreachable, http_status: nil, raw: nil }; end }
)
```

(or stop the server, edit the adapter to return `:unreachable` for one run, restart)

Submit the form again. Confirm submission still succeeds and the warning logs `[aliyun_captcha] fail-open: unreachable`.

- [ ] **Step 7: Verify fail-closed**

Edit the adapter or stub to return `:invalid`. Submit. Confirm: 422 response, no entry created, error message appears.

- [ ] **Step 8: Document any issues**

If anything doesn't work as expected, fix in place and add a regression test in the most relevant spec file before continuing.

- [ ] **Step 9: Commit any fixes**

```bash
git add -A
git commit -m "fix(aliyun_captcha): smoke-test fixes"
```

---

## Task 18: Full test sweep

**Files:** none

- [ ] **Step 1: Run the full module spec set**

Run:
```bash
bin/rspec spec/models/aliyun_captcha \
          spec/services/aliyun_captcha \
          spec/services/feature_modules/aliyun_captcha \
          spec/controllers/admin/maintenance/platform/aliyun_captcha \
          spec/controllers/admin/settings/modules/aliyun_captcha \
          spec/components/aliyun_captcha \
          spec/concerns/aliyun_captcha_protectable_spec.rb \
          spec/requests/public_pages_aliyun_captcha_spec.rb
```

Expected: 0 failures.

- [ ] **Step 2: Regression sweep**

Run:
```bash
bin/rspec spec/controllers/public_pages_controller_spec.rb \
          spec/models/page_spec.rb \
          spec/services/feature_modules/sms
```

Expected: no new failures versus the project's existing baseline (`docs/superpowers/plans/2026-05-10-baseline-failures.txt`). If any captcha-related test fails outside the module spec set, fix it before declaring done.

- [ ] **Step 3: Commit any final fixes**

```bash
git add -A
git commit -m "test(aliyun_captcha): regression-sweep fixes"
```

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| §3 Architecture flow | Tasks 8, 9, 14 |
| §4.1 PlatformSettings table | Task 1 |
| §4.2 Page#configuration_json toggle | Task 7 |
| §4.3 FeatureModule provisioner | Task 6 |
| §5 Public interface (Activity::Verify, Gateway) | Tasks 4, 5 |
| §6 Aliyun adapter | Tasks 2, 3 |
| §7 Errors | Task 2 |
| §8 Routes | Tasks 15, 16 |
| §9 FeatureModule registration | Task 6 |
| §10 Activity guards | Task 4 |
| §11 Controller integration | Tasks 8, 9 |
| §12 Stimulus + JS SDK | Task 12 |
| §13 Page editor toggle | Task 13 |
| §14 Authorization | Tasks 15, 16 |
| §15 i18n | Task 10 |
| §16 Testing | Each task carries its own RSpec; Task 18 sweeps |
| §17 Security (encryption, masked-field, scoping) | Tasks 1, 15 |

All 17 testing branches from §16 of the spec are covered:
- Models (Task 1) — singleton, encryption, configured?
- Adapter (Task 3) — golden signing, success/invalid/4xx/5xx/timeout
- Activity::Verify (Task 4) — every outcome, instrumentation, health-check side effect
- UpdatePlatformSettings (Task 15) — validation + masked-field-preservation
- Controllers (Tasks 9, 15, 16) — captcha required & valid / invalid / unreachable / module-off / page-off / credentials-missing; platform-owner gate; tenant scoping
- ViewComponents (Tasks 11, 13) — render? matrix
- Concern (Task 8) — full outcome dispatch
- Stimulus (Task 12) — assets:precompile sanity (full JS unit tests omitted; manual smoke covers in Task 17)
- Integration (Task 17) — end-to-end manual

**Placeholder scan:** No "TBD"/"TODO"/"add appropriate". Tasks 9 and 15 have small "if your project's factories differ, adjust to mirror the SMS spec" notes — these point to a concrete reference (the SMS specs) rather than asking the engineer to invent.

**Type consistency:**
- `AliyunCaptcha::Activities::Verify::Result.outcome` symbol set: `:success | :invalid | :unreachable | :configuration_error | :disabled` — used identically in Tasks 4, 5, 8, 9.
- `AliyunCaptcha::PlatformSettings#configured?` defined in Task 1, called in Tasks 4, 11, 16.
- Page accessor name `aliyun_captcha_enabled?` and writer `aliyun_captcha_enabled=` used consistently in Tasks 7, 8, 9, 11, 13, 16.
- Adapter return shape `{outcome:, http_status:, raw:}` defined in Task 3, consumed in Task 4.

---

**Plan complete and saved to `docs/superpowers/plans/2026-05-12-aliyun-captcha.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

**Which approach?**
