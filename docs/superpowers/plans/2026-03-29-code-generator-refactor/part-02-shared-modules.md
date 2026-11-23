# Part 2: Shared Modules — OperandConverter, ConditionBuilder, HttpRequestBuilder

## Task 3: Shared::OperandConverter

**Files:**
- Create: `app/services/code_generators/shared/operand_converter.rb`
- Test: `spec/services/code_generators/shared/operand_converter_spec.rb`

- [ ] **Step 1: Write OperandConverter spec**

```ruby
# spec/services/code_generators/shared/operand_converter_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::Shared::OperandConverter do
  let(:converter) { Class.new { include CodeGenerators::Shared::OperandConverter }.new }

  describe "#condition_operand_to_ruby" do
    it "converts ctx.field to ctx.dig(:field)" do
      expect(converter.condition_operand_to_ruby("ctx.user")).to eq("ctx.dig(:user)")
    end

    it "converts ctx.nested.path to ctx.dig(:nested, :path)" do
      expect(converter.condition_operand_to_ruby("ctx.user.email")).to eq("ctx.dig(:user, :email)")
    end

    it "converts 'signal' to ctx[:signal]" do
      expect(converter.condition_operand_to_ruby("signal")).to eq("ctx[:signal]")
    end

    it "converts 'ctx' to ctx" do
      expect(converter.condition_operand_to_ruby("ctx")).to eq("ctx")
    end

    it "passes through integers" do
      expect(converter.condition_operand_to_ruby("42")).to eq("42")
    end

    it "passes through floats" do
      expect(converter.condition_operand_to_ruby("3.14")).to eq("3.14")
    end

    it "wraps strings in quotes" do
      expect(converter.condition_operand_to_ruby("hello")).to eq("\"hello\"")
    end

    it "returns 'nil' for blank input" do
      expect(converter.condition_operand_to_ruby(nil)).to eq("nil")
      expect(converter.condition_operand_to_ruby("")).to eq("nil")
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/shared/operand_converter_spec.rb -fd`
Expected: FAIL — `uninitialized constant`

- [ ] **Step 3: Create OperandConverter module**

```ruby
# app/services/code_generators/shared/operand_converter.rb
# frozen_string_literal: true

module CodeGenerators
  module Shared
    module OperandConverter
      def condition_operand_to_ruby(operand)
        return "nil" if operand.blank?

        if operand.start_with?("ctx.")
          parts = operand.sub("ctx.", "").split(".")
          keys = parts.map { |p| ":#{p}" }.join(", ")
          "ctx.dig(#{keys})"
        elsif operand == "signal"
          "ctx[:signal]"
        elsif operand == "ctx"
          "ctx"
        elsif operand.match?(/\A\d+(\.\d+)?\z/)
          operand
        else
          operand.inspect
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec**

Run: `bundle exec rspec spec/services/code_generators/shared/operand_converter_spec.rb -fd`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/shared/operand_converter.rb \
        spec/services/code_generators/shared/operand_converter_spec.rb
git commit -m "feat: extract OperandConverter shared module"
```

---

## Task 4: Shared::ConditionBuilder

**Files:**
- Create: `app/services/code_generators/shared/condition_builder.rb`
- Test: `spec/services/code_generators/shared/condition_builder_spec.rb`

- [ ] **Step 1: Write ConditionBuilder spec**

```ruby
# spec/services/code_generators/shared/condition_builder_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::Shared::ConditionBuilder do
  let(:builder) do
    Class.new do
      include CodeGenerators::Shared::ConditionBuilder
    end.new
  end

  describe "#build_structured_condition" do
    it "returns 'true' for blank condition" do
      expect(builder.build_structured_condition(nil)).to eq("true")
      expect(builder.build_structured_condition({})).to eq("true")
    end

    it "builds a simple equality condition" do
      condition = { "leftOperand" => "ctx.status", "operator" => "==", "rightOperand" => "active" }
      result = builder.build_structured_condition(condition)
      expect(result).to eq('ctx.dig(:status) == "active"')
    end

    it "builds unary operators" do
      expect(builder.build_structured_condition(
        { "leftOperand" => "ctx.name", "operator" => "is_empty" }
      )).to eq("ctx.dig(:name).blank?")

      expect(builder.build_structured_condition(
        { "leftOperand" => "ctx.name", "operator" => "is_not_empty" }
      )).to eq("ctx.dig(:name).present?")

      expect(builder.build_structured_condition(
        { "leftOperand" => "ctx.flag", "operator" => "is_true" }
      )).to eq("!!ctx.dig(:flag)")

      expect(builder.build_structured_condition(
        { "leftOperand" => "ctx.val", "operator" => "is_nil" }
      )).to eq("ctx.dig(:val).nil?")
    end

    it "builds string operators" do
      expect(builder.build_structured_condition(
        { "leftOperand" => "ctx.name", "operator" => "contains", "rightOperand" => "test" }
      )).to eq('ctx.dig(:name).to_s.include?("test".to_s)')

      expect(builder.build_structured_condition(
        { "leftOperand" => "ctx.name", "operator" => "starts_with", "rightOperand" => "pre" }
      )).to eq('ctx.dig(:name).to_s.start_with?("pre".to_s)')
    end

    it "builds AND group conditions" do
      group = {
        "type" => "group",
        "operator" => "AND",
        "conditions" => [
          { "leftOperand" => "ctx.a", "operator" => "==", "rightOperand" => "1" },
          { "leftOperand" => "ctx.b", "operator" => "==", "rightOperand" => "2" }
        ]
      }
      result = builder.build_structured_condition(group)
      expect(result).to eq('(ctx.dig(:a) == "1" && ctx.dig(:b) == "2")')
    end

    it "builds OR group conditions" do
      group = {
        "type" => "group",
        "operator" => "OR",
        "conditions" => [
          { "leftOperand" => "ctx.x", "operator" => "is_true" },
          { "leftOperand" => "ctx.y", "operator" => "is_true" }
        ]
      }
      result = builder.build_structured_condition(group)
      expect(result).to eq("(!!ctx.dig(:x) || !!ctx.dig(:y))")
    end

    it "builds nested group conditions" do
      group = {
        "type" => "group",
        "operator" => "AND",
        "conditions" => [
          { "leftOperand" => "ctx.a", "operator" => "==", "rightOperand" => "1" },
          {
            "type" => "group",
            "operator" => "OR",
            "conditions" => [
              { "leftOperand" => "ctx.b", "operator" => "==", "rightOperand" => "2" },
              { "leftOperand" => "ctx.c", "operator" => "==", "rightOperand" => "3" }
            ]
          }
        ]
      }
      result = builder.build_structured_condition(group)
      expect(result).to include("&&")
      expect(result).to include("||")
    end

    it "returns 'true' for nil left operand with no operator" do
      condition = { "leftOperand" => nil, "operator" => nil }
      expect(builder.build_structured_condition(condition)).to eq("true")
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/shared/condition_builder_spec.rb -fd`
Expected: FAIL

- [ ] **Step 3: Create ConditionBuilder module**

```ruby
# app/services/code_generators/shared/condition_builder.rb
# frozen_string_literal: true

module CodeGenerators
  module Shared
    module ConditionBuilder
      include CodeGenerators::Shared::OperandConverter

      def build_structured_condition(condition)
        return "true" if condition.blank?

        if condition["type"] == "group"
          build_condition_group(condition)
        else
          build_single_condition(condition)
        end
      end

      private

      def build_condition_group(group)
        conditions = group["conditions"] || []
        return "true" if conditions.empty?

        ruby_op = group["operator"] == "OR" ? " || " : " && "
        parts = conditions.map { |c|
          c["type"] == "group" ? "(#{build_condition_group(c)})" : build_single_condition(c)
        }
        parts.length == 1 ? parts.first : "(#{parts.join(ruby_op)})"
      end

      def build_single_condition(condition)
        left = condition_operand_to_ruby(condition["leftOperand"])
        operator = condition["operator"]
        right = condition_operand_to_ruby(condition["rightOperand"])

        return "true" if left == "nil" && operator.blank?

        case operator
        when "is_empty"      then return "#{left}.blank?"
        when "is_not_empty"  then return "#{left}.present?"
        when "is_true"       then return "!!#{left}"
        when "is_false"      then return "!#{left}"
        when "is_nil"        then return "#{left}.nil?"
        when "matches_regex" then return "#{left}.to_s.match?(#{condition_operand_to_ruby(right)})"
        when "in_range"      then return "(#{condition_operand_to_ruby(right)}).include?(#{left})"
        when "is_type"       then return "#{left}.is_a?(#{right})"
        end

        ruby_op = case operator
                  when "==" then "=="
                  when "!=" then "!="
                  when ">"  then ">"
                  when ">=" then ">="
                  when "<"  then "<"
                  when "<=" then "<="
                  when "contains"    then return "#{left}.to_s.include?(#{right}.to_s)"
                  when "starts_with" then return "#{left}.to_s.start_with?(#{right}.to_s)"
                  when "ends_with"   then return "#{left}.to_s.end_with?(#{right}.to_s)"
                  else "=="
                  end

        "#{left} #{ruby_op} #{right}"
      end
    end
  end
end
```

- [ ] **Step 4: Run spec**

Run: `bundle exec rspec spec/services/code_generators/shared/condition_builder_spec.rb -fd`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/shared/condition_builder.rb \
        spec/services/code_generators/shared/condition_builder_spec.rb
git commit -m "feat: extract ConditionBuilder shared module"
```

---

## Task 5: Shared::HttpRequestBuilder

**Files:**
- Create: `app/services/code_generators/shared/http_request_builder.rb`
- Test: `spec/services/code_generators/shared/http_request_builder_spec.rb`

- [ ] **Step 1: Write HttpRequestBuilder spec**

```ruby
# spec/services/code_generators/shared/http_request_builder_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::Shared::HttpRequestBuilder do
  let(:builder) { Class.new { include CodeGenerators::Shared::HttpRequestBuilder }.new }

  describe "#build_http_request" do
    it "generates GET request code" do
      code = builder.build_http_request(
        method: "GET", url_expr: '"https://api.example.com"',
        response_var: "api_response", headers: [], auth_type: "none", auth_config: {}
      )
      expect(code).to include("Net::HTTP::Get")
      expect(code).to include("ctx[:api_response]")
      expect(code).to include("JSON.parse")
    end

    it "generates POST request code" do
      code = builder.build_http_request(
        method: "POST", url_expr: '"https://api.example.com"',
        response_var: "result", headers: [], auth_type: "none", auth_config: {},
        body_expr: '{ key: "value" }'
      )
      expect(code).to include("Net::HTTP::Post")
      expect(code).to include("ctx[:result]")
      expect(code).to include('{ key: "value" }.to_json')
    end

    it "includes bearer auth header" do
      code = builder.build_http_request(
        method: "GET", url_expr: '"https://api.example.com"',
        response_var: "r", headers: [],
        auth_type: "bearer", auth_config: { "authToken" => "ctx[:token]" }
      )
      expect(code).to include("Authorization")
      expect(code).to include("Bearer")
    end

    it "includes custom headers" do
      code = builder.build_http_request(
        method: "GET", url_expr: '"https://api.example.com"',
        response_var: "r",
        headers: [{ "key" => "X-Custom", "value" => "test" }],
        auth_type: "none", auth_config: {}
      )
      expect(code).to include('request["X-Custom"] = "test"')
    end
  end

  describe "#build_headers_code" do
    it "returns empty string for no headers and no auth" do
      expect(builder.build_headers_code([], "none", {})).to eq("")
    end

    it "builds basic auth" do
      code = builder.build_headers_code([], "basic", {
        "authUsername" => "user", "authPassword" => "pass"
      })
      expect(code).to include("basic_auth")
    end

    it "builds apiKey auth" do
      code = builder.build_headers_code([], "apiKey", {
        "apiKeyHeader" => "X-API-Key", "apiKeyValue" => "ctx[:key]"
      })
      expect(code).to include("X-API-Key")
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

Run: `bundle exec rspec spec/services/code_generators/shared/http_request_builder_spec.rb -fd`
Expected: FAIL

- [ ] **Step 3: Create HttpRequestBuilder module**

```ruby
# app/services/code_generators/shared/http_request_builder.rb
# frozen_string_literal: true

module CodeGenerators
  module Shared
    module HttpRequestBuilder
      def build_http_request(method:, url_expr:, response_var:, headers: [], auth_type: "none", auth_config: {}, body_expr: nil)
        if method.upcase == "GET"
          build_get_request_code(url_expr, headers, auth_type, auth_config, response_var)
        else
          build_mutating_request_code(method, url_expr, headers, auth_type, auth_config, body_expr, response_var)
        end
      end

      def build_headers_code(headers, auth_type, auth_config)
        lines = (headers || []).map do |h|
          "request[\"#{h['key']}\"] = \"#{h['value']}\""
        end

        case auth_type
        when "bearer"
          token = auth_config["authToken"] || "ctx[:api_token]"
          lines << "request[\"Authorization\"] = \"Bearer \#{#{token}}\""
        when "basic"
          username = auth_config["authUsername"] || "ctx[:username]"
          password = auth_config["authPassword"] || "ctx[:password]"
          lines << "request.basic_auth(#{username}, #{password})"
        when "apiKey"
          key_header = auth_config["apiKeyHeader"] || "X-API-Key"
          key_value = auth_config["apiKeyValue"] || "ctx[:api_key]"
          lines << "request[\"#{key_header}\"] = #{key_value}"
        end

        lines.empty? ? "" : lines.join("\n")
      end

      private

      def build_get_request_code(url_expr, headers, auth_type, auth_config, response_var)
        headers_code = build_headers_code(headers, auth_type, auth_config)
        parts = [
          "uri = URI(#{url_expr})",
          "request = Net::HTTP::Get.new(uri)"
        ]
        parts << headers_code if headers_code.present?
        parts += [
          "response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == \"https\") { |http| http.request(request) }",
          "ctx[:#{response_var}] = JSON.parse(response.body, symbolize_names: true)",
          "response.is_a?(Net::HTTPSuccess)"
        ]
        parts.join("\n")
      end

      def build_mutating_request_code(method, url_expr, headers, auth_type, auth_config, body_expr, response_var)
        headers_code = build_headers_code(headers, auth_type, auth_config)
        body = body_expr || "{}"
        parts = [
          "uri = URI(#{url_expr})",
          "http = Net::HTTP.new(uri.host, uri.port)",
          "http.use_ssl = uri.scheme == \"https\"",
          "request = Net::HTTP::#{method.capitalize}.new(uri.path)",
          "request[\"Content-Type\"] = \"application/json\""
        ]
        parts << headers_code if headers_code.present?
        parts += [
          "request.body = #{body}.to_json",
          "response = http.request(request)",
          "ctx[:#{response_var}] = JSON.parse(response.body, symbolize_names: true)",
          "response.is_a?(Net::HTTPSuccess)"
        ]
        parts.join("\n")
      end
    end
  end
end
```

- [ ] **Step 4: Run spec**

Run: `bundle exec rspec spec/services/code_generators/shared/http_request_builder_spec.rb -fd`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/shared/http_request_builder.rb \
        spec/services/code_generators/shared/http_request_builder_spec.rb
git commit -m "feat: extract HttpRequestBuilder shared module"
```

- [ ] **Step 6: Run all shared module specs together**

Run: `bundle exec rspec spec/services/code_generators/ -fd`
Expected: All tests PASS (interface, base generator, and all 3 shared modules)
