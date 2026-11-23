# frozen_string_literal: true

require "rails_helper"

RSpec.describe "FlowchartRuntime facade contract" do
  FACADE_ROOT = Rails.root.join("app/services/flowchart_runtime")

  # The contract list is DERIVED from the namespace rather than hand-maintained,
  # so a newly added facade cannot be silently omitted from the audit. A file
  # may only opt out by being named here together with the reason it has no
  # error boundary to narrow. An exemption for a file that no longer exists is
  # itself a failure, so stale entries cannot accumulate.
  CONTRACT_EXEMPT = {
    "authentication" =>
      "Credential predicates return nil for absent, untrusted or rejected " \
      "credentials. Warden/Devise own authentication; framework and database " \
      "failures must propagate unchanged rather than become credential failures.",
    "condition_input" =>
      "Pure normalizer for property-editor input: every entry point returns " \
      "nil/false/[] for unusable input and never raises, so there is no error " \
      "boundary to narrow. Callers turn the nil into a validation error.",
    "errors" =>
      "Pure collector run by the generated failure step: it only reads ctx and " \
      "returns an Array of messages, so there is no error boundary to narrow.",
    "outputs" =>
      "Pure selector for generated merge reads: it returns the value of the first " \
      "present ctx key (or nil) and never raises, so there is no error boundary to narrow.",
    "loop_state" =>
      "Pure Prism rewriter for loop-region ctx access: it returns the original or " \
      "rewritten body and never raises, so there is no error boundary to narrow.",
    "registration" =>
      "Every refusal is a Step.fail or record_invalid result on ctx, never a raise. " \
      "It delegates to RegisterMember, IssueSignInLink and People::Claim; database " \
      "failures must propagate so the submission transaction rolls back.",
    "runtime_flowchart" =>
      "Read-only delegator that ActivityTracer and ActivityClassBuilder wrap around a " \
      "Flowchart record, not a facade generated steps call. Generation and lookup " \
      "failures propagate to the tracer, which owns the execution error boundary.",
    "handoff" =>
      "Parks a module handoff on ctx or fails the step with a translated code. It " \
      "never raises, so there is no error boundary to narrow.",
    "journey_skips" =>
      "Parks the journey step keys to leave out on the submission outcome, or does " \
      "nothing outside a journey. It never raises, so there is no error boundary to narrow.",
    "page_run" =>
      "The page-submission savepoint is the error boundary: HANDOFF_ERRORS become a " \
      "refused Result, and StandardError is logged then refused so a visitor never " \
      "sees a 500."
  }.freeze

  # Delegation is an error boundary too: SMS owns no SDK protocol or error
  # translation. Its public facade preserves the gateway's domain exceptions.
  SHARED_ERROR_BOUNDARIES = {
    "sms" => { call: "::Sms::Gateway.send(", error: "Sms::Errors::Error" }
  }.freeze

  facade_files = FACADE_ROOT.children
                            .select { |path| path.file? && path.extname == ".rb" }
                            .map { |path| path.basename(".rb").to_s }
                            .sort

  it "derives the contract list from the FlowchartRuntime namespace" do
    expect(facade_files).not_to be_empty
    expect(facade_files).to include("lock", "backoff", "circuit_breaker", "job_schedule", "cache_key")
  end

  it "does not carry exemptions for files that no longer exist" do
    expect(CONTRACT_EXEMPT.keys - facade_files).to be_empty
    expect(SHARED_ERROR_BOUNDARIES.keys - facade_files).to be_empty
    expect(SHARED_ERROR_BOUNDARIES.keys & CONTRACT_EXEMPT.keys).to be_empty
  end

  (facade_files - CONTRACT_EXEMPT.keys).each do |file|
    it "#{file} exposes a narrow error boundary without broad or optional fallbacks" do
      path = FACADE_ROOT.join("#{file}.rb")

      expect(path).to exist
      source = path.read
      if (boundary = SHARED_ERROR_BOUNDARIES[file])
        expect(source).to include(boundary.fetch(:call))
        expect(boundary.fetch(:error).constantize).to be < StandardError
        expect(source).not_to match(/\brescue\b|\bclass\s+Error\b|\bError\s*=/)
      else
        expect(source).to include("class Error <")
      end
      expect(source).not_to match(/rescue\s+(?:StandardError|Exception)\b/)
      expect(source).not_to include("defined?(")
      expect(source).not_to include("const_defined?(")
    end
  end

  invalid_calls = {
    "archive" => [FlowchartRuntime::Archive::Error, -> { FlowchartRuntime::Archive.compress(["bad"]) }],
    "backoff" => ["FlowchartRuntime::Backoff::Error", -> {
      FlowchartRuntime::Backoff.delay_for(0, strategy: "fixed", initial_delay: 1)
    }],
    "barcode" => [FlowchartRuntime::Barcode::Error, -> { FlowchartRuntime::Barcode.generate("x", output: nil) }],
    "barcode_svg_label" => ["FlowchartRuntime::BarcodeSvgLabel::Error", -> {
      FlowchartRuntime::BarcodeSvgLabel.apply("<svg/>", text: "x", font: "ComicSans")
    }],
    "business_hours" => ["FlowchartRuntime::BusinessHours::Error", -> {
      FlowchartRuntime::BusinessHours.open?(schedule: {}, at: Time.utc(2026, 1, 1), timezone: "Not/AZone")
    }],
    "cache_key" => ["FlowchartRuntime::CacheKey::Error", -> { FlowchartRuntime::CacheKey.scoped(nil, "key") }],
    "circuit_breaker" => ["FlowchartRuntime::CircuitBreaker::Error", -> {
      FlowchartRuntime::CircuitBreaker.cache_key(1, "  ")
    }],
    "http" => ["FlowchartRuntime::Http::Error", -> { FlowchartRuntime::Http.request({}, :get, "") }],
    "idempotency" => ["FlowchartRuntime::Idempotency::Error", -> {
      FlowchartRuntime::Idempotency.claim({ customer_id: 1 }, "  ", ttl: 30)
    }],
    "json" => ["FlowchartRuntime::Json::Error", -> { FlowchartRuntime::Json.parse("{", max_bytes: 16) }],
    "rate_limiter" => ["FlowchartRuntime::RateLimiter::Error", -> {
      FlowchartRuntime::RateLimiter.allow?({ customer_id: 1 }, " ", capacity: 1, window: 60)
    }],
    "run_context" => ["FlowchartRuntime::RunContext::Error", -> { FlowchartRuntime::RunContext.with_deadline(0) { } }],
    "step" => ["FlowchartRuntime::Step::Error", -> { FlowchartRuntime::Step.fail({}, nil) }],
    "crypto" => ["FlowchartRuntime::Crypto::Error", -> { FlowchartRuntime.const_get(:Crypto).hmac(nil, key: "k", data: "d") }],
    "config_resolver" => ["FlowchartRuntime::ConfigResolver::Error", -> {
      FlowchartRuntime::ConfigResolver.resolve({ "overrides" => [{ "when" => { "role" => "admin" }, "apply" => {} }] }, nil)
    }],
    "context_resolver" => ["FlowchartRuntime::ContextResolver::Error", -> { FlowchartRuntime::ContextResolver.resolve("ctx.user.id", nil) }],
    "expression_evaluator" => ["FlowchartRuntime::ExpressionEvaluator::Error", -> { FlowchartRuntime::ExpressionEvaluator.evaluate("1 +", {}) }],
    "formula_compiler" => ["FlowchartRuntime::FormulaCompiler::Error", -> { FlowchartRuntime::FormulaCompiler.compile("unknown + 1", []) }],
    "invocable" => ["FlowchartRuntime::Invocable::Error", -> { FlowchartRuntime::Invocable.service!("not a class name") }],
    "job_schedule" => ["FlowchartRuntime::JobSchedule::Error", -> { FlowchartRuntime::JobSchedule.enqueue!("NotAJobClass") }],
    "join_resolver" => ["FlowchartRuntime::JoinResolver::Error", -> {
      FlowchartRuntime::JoinResolver.new(source_entity: nil, target_entity: nil, bridge_entity: nil, customer_id: nil)
    }],
    "json_path_validator" => ["FlowchartRuntime::JsonPathValidator::Error", -> { FlowchartRuntime::JsonPathValidator.safe_json_path!("bad path") }],
    "jwt" => [FlowchartRuntime::Jwt::Error, -> { FlowchartRuntime::Jwt.encode({}, "not-pem", algorithm: "RS256") }],
    "lock" => [FlowchartRuntime::Lock::Error, -> { FlowchartRuntime::Lock.acquire(nil, "key", "token", ttl: 1) }],
    "mail_attachments" => ["FlowchartRuntime::MailAttachments::Error", -> {
      FlowchartRuntime::MailAttachments.encode("report.bin" => { content: 123 })
    }],
    "mail_headers" => ["FlowchartRuntime::MailHeaders::Error", -> {
      FlowchartRuntime::MailHeaders.addresses!("to@example.test\nBcc: attacker@evil.test")
    }],
    "qr_code" => [FlowchartRuntime::QrCode::Error, -> { FlowchartRuntime::QrCode.generate("x", output: nil) }],
    "query_builder" => ["FlowchartRuntime::QueryBuilder::Error", -> { FlowchartRuntime::QueryBuilder.for_entity(nil, customer_id: 1).execute }],
    "query_logger" => ["FlowchartRuntime::QueryLogger::Error", -> { FlowchartRuntime::QueryLogger.capture }],
    "sanitize" => [FlowchartRuntime::Sanitize::Error, -> { FlowchartRuntime::Sanitize.html("x", mode: nil) }],
    "sms" => ["Sms::Errors::Error", -> {
      FlowchartRuntime::Sms.send_template(customer: nil, to: [], template_key: "verify_code")
    }],
    "template" => [FlowchartRuntime::Template::Error, -> { FlowchartRuntime::Template.render("x", {}, engine: nil) }],
    "where_clause_builder" => ["FlowchartRuntime::WhereClauseBuilder::Error", -> {
      FlowchartRuntime::WhereClauseBuilder.apply(nil, { "rules" => [{ "field" => "id", "op" => "==", "value" => 1 }] }, {})
    }]
  }

  invalid_calls.each do |file, (error_class, invocation)|
    owner = SHARED_ERROR_BOUNDARIES.key?(file) ? "shared domain" : "namespaced"
    it "#{file} raises its #{owner} Error for invalid public input" do
      expected_error = error_class.is_a?(String) ? error_class.constantize : error_class
      expect(&invocation).to raise_error(expected_error)
    end
  end

  it "only probes facades that are part of the contract" do
    expect(invalid_calls.keys - facade_files).to be_empty
    expect(invalid_calls.keys & CONTRACT_EXEMPT.keys).to be_empty
    expect(SHARED_ERROR_BOUNDARIES.keys - invalid_calls.keys).to be_empty
  end

  it "SMS preserves the gateway transport exception identity and ambiguous acceptance facts" do
    customer = instance_double(Customer, id: 1)
    error = Sms::Errors::TransportError.new(I18n.t("sms.failures.send_never_confirmed"),
                                           vendor_message_id: "SM-AMBIGUOUS", payload: { "status" => "accepted" })
    expect(Sms::Gateway).to receive(:send).with(customer: customer, to: "+8613800138000", template_key: "verify_code",
                                               vars: { "code" => "1234" }, idempotency_key: "notification-1", expires_at: nil)
      .and_raise(error)

    expect {
      FlowchartRuntime::Sms.send_template(customer: customer, to: "+8613800138000", template_key: "verify_code",
                                         vars: { "code" => "1234" }, idempotency_key: "notification-1")
    }.to raise_error(Sms::Errors::TransportError) do |raised|
      expect(raised).to equal(error)
      expect(raised.vendor_message_id).to eq("SM-AMBIGUOUS")
      expect(raised.payload).to eq("status" => "accepted")
    end
  end

  it "authentication returns nil for missing or untrusted credentials under its predicate exemption" do
    expect(FlowchartRuntime::Authentication.from_request(nil).user).to be_nil
    expect(FlowchartRuntime::Authentication.session(context: { user_id: 1 }, customer_id: 1)).to be_nil
    expect(FlowchartRuntime::Authentication.password(user: nil, password: "untrusted", customer_id: 1)).to be_nil
  end

  it "authentication preserves framework database errors rather than converting them to rejection" do
    request = ActionDispatch::Request.new({})
    warden = Warden::Proxy.new(request.env, Warden::Manager.new(nil))
    request.env["warden"] = warden
    allow(warden).to receive(:user).with(:user).and_raise(ActiveRecord::ConnectionNotEstablished, "database unavailable")

    expect { FlowchartRuntime::Authentication.from_request(request) }
      .to raise_error(ActiveRecord::ConnectionNotEstablished, "database unavailable")
  end
end
