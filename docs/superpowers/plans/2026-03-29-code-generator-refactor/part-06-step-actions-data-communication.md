# Part 6: Step Action Generators — Data + Communication

## Task 12: Data Operation Generators (4 files)

**Files:**
- Create: `app/services/code_generators/step_actions/assign_value_generator.rb`
- Create: `app/services/code_generators/step_actions/transform_generator.rb`
- Create: `app/services/code_generators/step_actions/calculate_generator.rb`
- Create: `app/services/code_generators/step_actions/log_generator.rb`
- Test: one spec per generator in `spec/services/code_generators/step_actions/`

**Source reference:** `app/services/activity_generator/data_steps.rb`

- [ ] **Step 1: Create all 4 data operation generators**

```ruby
# app/services/code_generators/step_actions/assign_value_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module StepActions
    class AssignValueGenerator < BaseGenerator
      include Shared::OperandConverter

      generator_metadata do
        description "Assigns a value to a context variable"
        category :data_operations
        version "1.0.0"
      end

      input_schema  # varies by value type
      output_schema :result

      def generate
        target = config["targetVar"] || "result"
        value_type = config["valueType"] || "expression"

        value_code = case value_type
                     when "string"  then (config["stringValue"] || "").inspect
                     when "integer" then (config["integerValue"] || 0).to_s
                     when "boolean" then (config["booleanValue"] || "false").to_s
                     else                config["valueExpression"] || "nil"
                     end

        <<~RUBY.chomp
          ctx[:#{target}] = #{value_code}
          true
        RUBY
      end

      def validate_config(cfg)
        errors = []
        errors << "Target variable is required" if cfg["targetVar"].blank?
        errors
      end

      def example_output
        "ctx[:result] = \"hello\"\ntrue"
      end
    end
  end
end
```

```ruby
# app/services/code_generators/step_actions/transform_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module StepActions
    class TransformGenerator < BaseGenerator
      generator_metadata do
        description "Applies data transformation (mapFields, formatDate, convertType)"
        category :data_operations
        version "1.0.0"
      end

      input_schema  :data
      output_schema :result

      def generate
        transform_type = config["transformType"] || "custom"
        source = config["sourceField"] || "data"
        target = config["targetField"] || "result"
        description = element["description"].presence

        case transform_type
        when "mapFields"
          generate_map_fields(source, target)
        when "formatDate"
          fmt = config["dateFormat"] || "%Y-%m-%d"
          "ctx[:#{target}] = ctx[:#{source}].strftime(\"#{fmt}\")\ntrue"
        when "convertType"
          generate_convert_type(source, target)
        else
          comment = description ? "# Transform: #{description}" : "# Transform data"
          "#{comment}\ntrue"
        end
      end

      def validate_config(cfg)
        []
      end

      def example_output
        "ctx[:result] = ctx[:data].slice(:name, :email)\ntrue"
      end

      private

      def generate_map_fields(source, target)
        mappings = config["fieldMappings"] || []
        if mappings.any?
          keys = mappings.map { |m| ":#{m['key']}" }.join(", ")
          renames = mappings.select { |m| m["value"].present? && m["key"] != m["value"] }
          rename_hash = renames.map { |m| "#{m['key']}: :#{m['value']}" }.join(", ")
          if rename_hash.present?
            "ctx[:#{target}] = ctx[:#{source}].slice(#{keys}).transform_keys({ #{rename_hash} })\ntrue"
          else
            "ctx[:#{target}] = ctx[:#{source}].slice(#{keys})\ntrue"
          end
        else
          "ctx[:#{target}] = ctx[:#{source}]\ntrue"
        end
      end

      def generate_convert_type(source, target)
        convert_to = config["convertTo"] || "string"
        if convert_to == "array"
          "ctx[:#{target}] = Array.wrap(ctx[:#{source}])\ntrue"
        else
          method = case convert_to
                   when "integer" then "to_i"
                   when "float"   then "to_f"
                   when "json"    then "to_json"
                   else "to_s"
                   end
          "ctx[:#{target}] = ctx[:#{source}].#{method}\ntrue"
        end
      end
    end
  end
end
```

```ruby
# app/services/code_generators/step_actions/calculate_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module StepActions
    class CalculateGenerator < BaseGenerator
      include Shared::OperandConverter

      generator_metadata do
        description "Performs aggregate calculations (sum, count, avg, min, max) on collections"
        category :data_operations
        version "1.0.0"
      end

      input_schema  :items
      output_schema :result

      def generate
        operation = config["operation"] || "count"
        collection = config["collectionExpression"] || "ctx[:items]"
        field = config["fieldName"]
        result_var = config["resultVar"] || "result"

        code = case operation
               when "sum"
                 field ? "#{collection}.sum { |r| r[:#{field}] }" : "#{collection}.sum"
               when "count"
                 "#{collection}.count"
               when "avg"
                 field ? "#{collection}.sum { |r| r[:#{field}] }.to_f / #{collection}.size" : "#{collection}.sum.to_f / #{collection}.size"
               when "min"
                 field ? "#{collection}.min_by { |r| r[:#{field}] }[:#{field}]" : "#{collection}.min"
               when "max"
                 field ? "#{collection}.max_by { |r| r[:#{field}] }[:#{field}]" : "#{collection}.max"
               when "custom"
                 config["customExpression"] || "nil"
               else
                 "#{collection}.count"
               end

        <<~RUBY.chomp
          ctx[:#{result_var}] = #{code}
          true
        RUBY
      end

      def validate_config(cfg)
        errors = []
        if cfg["operation"] == "custom" && cfg["customExpression"].blank?
          errors << "Custom expression is required for custom operation"
        end
        errors
      end

      def example_output
        "ctx[:result] = ctx[:items].count\ntrue"
      end
    end
  end
end
```

```ruby
# app/services/code_generators/step_actions/log_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module StepActions
    class LogGenerator < BaseGenerator
      generator_metadata do
        description "Writes log entries via Rails.logger or audit trail"
        category :data_operations
        version "1.0.0"
      end

      input_schema  # varies
      output_schema # none (side effect only)

      def generate
        level = config["logLevel"] || "info"
        message = config["messageTemplate"] || "Log entry"
        log_type = config["logType"] || "rails_logger"

        if log_type == "audit_trail"
          audit_data = config["auditDataExpression"] || "{}"
          <<~RUBY.chomp
            AuditLog.create!(action: #{message.inspect}, data: #{audit_data}, customer_id: ctx[:customer_id])
            true
          RUBY
        else
          <<~RUBY.chomp
            Rails.logger.#{level}(#{message.inspect})
            true
          RUBY
        end
      end

      def validate_config(cfg)
        errors = []
        level = cfg["logLevel"]
        unless level.blank? || %w[debug info warn error fatal].include?(level)
          errors << "Invalid log level: #{level}"
        end
        errors
      end

      def example_output
        "Rails.logger.info(\"Log entry\")\ntrue"
      end
    end
  end
end
```

- [ ] **Step 2: Write specs for all 4**

```ruby
# spec/services/code_generators/step_actions/assign_value_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::StepActions::AssignValueGenerator do
  let(:element) { { "config" => { "targetVar" => "result", "valueType" => "string", "stringValue" => "hello" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates string assignment" do
    expect(described_class.new(element, context).generate).to include('ctx[:result] = "hello"')
  end

  it "generates integer assignment" do
    el = { "config" => { "targetVar" => "count", "valueType" => "integer", "integerValue" => 42 } }
    expect(described_class.new(el, {}).generate).to include("ctx[:count] = 42")
  end

  it "generates expression assignment" do
    el = { "config" => { "targetVar" => "x", "valueType" => "expression", "valueExpression" => "ctx[:a] + ctx[:b]" } }
    expect(described_class.new(el, {}).generate).to include("ctx[:x] = ctx[:a] + ctx[:b]")
  end
end
```

```ruby
# spec/services/code_generators/step_actions/transform_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::StepActions::TransformGenerator do
  let(:element) { { "config" => { "transformType" => "custom" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates formatDate transform" do
    el = { "config" => { "transformType" => "formatDate", "sourceField" => "date", "dateFormat" => "%Y-%m-%d" } }
    expect(described_class.new(el, {}).generate).to include("strftime")
  end

  it "generates convertType to integer" do
    el = { "config" => { "transformType" => "convertType", "sourceField" => "val", "convertTo" => "integer" } }
    expect(described_class.new(el, {}).generate).to include(".to_i")
  end

  it "generates mapFields transform" do
    el = { "config" => { "transformType" => "mapFields", "sourceField" => "data", "targetField" => "result", "fieldMappings" => [{ "key" => "name", "value" => "name" }] } }
    expect(described_class.new(el, {}).generate).to include("slice(:name)")
  end
end
```

```ruby
# spec/services/code_generators/step_actions/calculate_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::StepActions::CalculateGenerator do
  let(:element) { { "config" => { "operation" => "count" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates count" do
    expect(described_class.new(element, context).generate).to include(".count")
  end

  it "generates sum with field" do
    el = { "config" => { "operation" => "sum", "fieldName" => "price", "collectionExpression" => "ctx[:orders]" } }
    expect(described_class.new(el, {}).generate).to include("sum { |r| r[:price] }")
  end

  it "generates avg" do
    el = { "config" => { "operation" => "avg", "collectionExpression" => "ctx[:items]" } }
    expect(described_class.new(el, {}).generate).to include(".to_f / ")
  end
end
```

```ruby
# spec/services/code_generators/step_actions/log_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::StepActions::LogGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "defaults to Rails.logger.info" do
    expect(described_class.new(element, context).generate).to include("Rails.logger.info")
  end

  it "supports audit trail" do
    el = { "config" => { "logType" => "audit_trail", "messageTemplate" => "action" } }
    expect(described_class.new(el, {}).generate).to include("AuditLog.create!")
  end

  it "supports custom log level" do
    el = { "config" => { "logLevel" => "error", "messageTemplate" => "oops" } }
    expect(described_class.new(el, {}).generate).to include("Rails.logger.error")
  end
end
```

- [ ] **Step 3: Run specs**

Run: `bundle exec rspec spec/services/code_generators/step_actions/assign_value_generator_spec.rb spec/services/code_generators/step_actions/transform_generator_spec.rb spec/services/code_generators/step_actions/calculate_generator_spec.rb spec/services/code_generators/step_actions/log_generator_spec.rb -fd`
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add app/services/code_generators/step_actions/assign_value_generator.rb \
        app/services/code_generators/step_actions/transform_generator.rb \
        app/services/code_generators/step_actions/calculate_generator.rb \
        app/services/code_generators/step_actions/log_generator.rb \
        spec/services/code_generators/step_actions/assign_value_generator_spec.rb \
        spec/services/code_generators/step_actions/transform_generator_spec.rb \
        spec/services/code_generators/step_actions/calculate_generator_spec.rb \
        spec/services/code_generators/step_actions/log_generator_spec.rb
git commit -m "feat: add 4 data operation step action generators"
```

---

## Task 13: Communication Generators (4 files)

**Files:**
- Create: `app/services/code_generators/step_actions/api_call_generator.rb`
- Create: `app/services/code_generators/step_actions/send_email_generator.rb`
- Create: `app/services/code_generators/step_actions/send_webhook_generator.rb`
- Create: `app/services/code_generators/step_actions/notify_generator.rb`
- Test: one spec per generator

**Source reference:** `app/services/activity_generator/communication_steps.rb`

- [ ] **Step 1: Create all 4 communication generators**

```ruby
# app/services/code_generators/step_actions/api_call_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module StepActions
    class ApiCallGenerator < BaseGenerator
      include Shared::HttpRequestBuilder

      generator_metadata do
        description "Makes an external HTTP request (GET/POST/PUT/PATCH/DELETE)"
        category :communication
        version "1.0.0"
      end

      # Register under both normalized and original action names
      def self.registered_names
        ["api_call", "API_call"]
      end

      input_schema  :api_url
      output_schema :api_response

      def generate
        method = config["httpMethod"] || "GET"
        url_expr = config["url"] || "ctx[:api_url]"
        response_var = config["responseVar"] || "api_response"
        auth_type = config["authType"] || "none"
        headers = config["headers"] || []

        if method.upcase == "GET"
          build_http_request(
            method: method, url_expr: url_expr, response_var: response_var,
            headers: headers, auth_type: auth_type, auth_config: config
          )
        else
          build_http_request(
            method: method, url_expr: url_expr, response_var: response_var,
            headers: headers, auth_type: auth_type, auth_config: config,
            body_expr: config["bodyTemplate"] || "{}"
          )
        end
      end

      def validate_config(cfg)
        errors = []
        errors << "URL is required" if cfg["url"].blank?
        errors
      end

      def example_output
        "uri = URI(\"https://api.example.com\")\nrequest = Net::HTTP::Get.new(uri)\n..."
      end
    end
  end
end
```

```ruby
# app/services/code_generators/step_actions/send_email_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module StepActions
    class SendEmailGenerator < BaseGenerator
      generator_metadata do
        description "Sends an email using ActionMailer or custom mailer"
        category :communication
        version "1.0.0"
      end

      input_schema  :email
      output_schema # none (side effect)

      def generate
        mailer_method = config["mailerMethod"] || "default"
        to = config["toExpression"] || "ctx[:email]"
        subject = config["subject"] || "Notification"

        if mailer_method == "custom"
          mailer_class = config["mailerClass"] || "ApplicationMailer"
          mailer_action = config["mailerAction"] || "notify"
          <<~RUBY.chomp
            #{mailer_class}.#{mailer_action}(#{to}).deliver_later
            true
          RUBY
        else
          body = config["bodyTemplate"] || ""
          <<~RUBY.chomp
            ActionMailer::Base.mail(to: #{to}, subject: #{subject.inspect}, body: #{body.inspect}).deliver_later
            true
          RUBY
        end
      end

      def validate_config(cfg)
        errors = []
        errors << "Recipient expression is required" if cfg["toExpression"].blank?
        errors
      end

      def example_output
        "ActionMailer::Base.mail(to: ctx[:email], subject: \"Notification\", body: \"\").deliver_later\ntrue"
      end
    end
  end
end
```

```ruby
# app/services/code_generators/step_actions/send_webhook_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module StepActions
    class SendWebhookGenerator < BaseGenerator
      include Shared::HttpRequestBuilder

      generator_metadata do
        description "Sends an HTTP POST webhook with optional HMAC signing"
        category :communication
        version "1.0.0"
      end

      input_schema  :webhook_url
      output_schema :webhook_response

      def generate
        url = config["url"] || "ctx[:webhook_url]"
        payload = config["payloadExpression"] || "{}"
        response_var = config["responseVar"] || "webhook_response"
        secret = config["secretExpression"]
        headers = config["headers"] || []

        headers_code = build_headers_code(headers, "none", config)

        hmac_code = if secret.present?
          <<~RUBY
            payload_json = #{payload}.to_json
            signature = OpenSSL::HMAC.hexdigest("SHA256", #{secret}, payload_json)
            request["X-Signature"] = signature
            request.body = payload_json
          RUBY
        else
          "request.body = #{payload}.to_json\n"
        end

        parts = [
          "uri = URI(#{url})",
          "http = Net::HTTP.new(uri.host, uri.port)",
          "http.use_ssl = uri.scheme == \"https\"",
          "request = Net::HTTP::Post.new(uri.path)",
          "request[\"Content-Type\"] = \"application/json\""
        ]
        parts << headers_code if headers_code.present?
        parts << hmac_code.strip
        parts += [
          "response = http.request(request)",
          "ctx[:#{response_var}] = JSON.parse(response.body, symbolize_names: true)",
          "response.is_a?(Net::HTTPSuccess)"
        ]
        parts.join("\n")
      end

      def validate_config(cfg)
        errors = []
        errors << "URL is required" if cfg["url"].blank?
        errors
      end

      def example_output
        "uri = URI(ctx[:webhook_url])\n..."
      end
    end
  end
end
```

```ruby
# app/services/code_generators/step_actions/notify_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module StepActions
    class NotifyGenerator < BaseGenerator
      generator_metadata do
        description "Sends a notification via email, slack, or SMS channel"
        category :communication
        version "1.0.0"
      end

      input_schema  :recipient
      output_schema :notification_sent

      def generate
        channel = config["channel"] || "email"
        recipient = config["recipientExpression"] || "ctx[:recipient]"
        message = config["messageTemplate"] || "Notification"

        case channel
        when "slack"
          <<~RUBY.chomp
            SlackNotifier.notify(channel: #{recipient}, message: #{message.inspect})
            ctx[:notification_sent] = true
            true
          RUBY
        when "sms"
          <<~RUBY.chomp
            SmsService.send_message(to: #{recipient}, body: #{message.inspect})
            ctx[:notification_sent] = true
            true
          RUBY
        else
          <<~RUBY.chomp
            ctx[:notification_sent] = true
            true
          RUBY
        end
      end

      def validate_config(cfg)
        []
      end

      def example_output
        "ctx[:notification_sent] = true\ntrue"
      end
    end
  end
end
```

- [ ] **Step 2: Write specs**

```ruby
# spec/services/code_generators/step_actions/api_call_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::StepActions::ApiCallGenerator do
  let(:element) { { "config" => { "url" => '"https://api.example.com"', "httpMethod" => "GET" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "registers under both api_call and API_call" do
    expect(described_class.registered_names).to include("api_call", "API_call")
  end

  it "generates GET request" do
    expect(described_class.new(element, context).generate).to include("Net::HTTP::Get")
  end

  it "generates POST request" do
    el = { "config" => { "url" => '"https://api.example.com"', "httpMethod" => "POST" } }
    expect(described_class.new(el, {}).generate).to include("Net::HTTP::Post")
  end

  it "includes auth headers when configured" do
    el = { "config" => { "url" => '"https://api.example.com"', "httpMethod" => "GET", "authType" => "bearer", "authToken" => "ctx[:token]" } }
    expect(described_class.new(el, {}).generate).to include("Authorization")
  end
end
```

```ruby
# spec/services/code_generators/step_actions/send_email_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::StepActions::SendEmailGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates default mailer call" do
    expect(described_class.new(element, context).generate).to include("ActionMailer::Base.mail")
  end

  it "generates custom mailer call" do
    el = { "config" => { "mailerMethod" => "custom", "mailerClass" => "UserMailer", "mailerAction" => "welcome" } }
    expect(described_class.new(el, {}).generate).to include("UserMailer.welcome")
  end
end
```

```ruby
# spec/services/code_generators/step_actions/send_webhook_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::StepActions::SendWebhookGenerator do
  let(:element) { { "config" => { "url" => "ctx[:webhook_url]" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates POST webhook code" do
    code = described_class.new(element, context).generate
    expect(code).to include("Net::HTTP::Post")
    expect(code).to include("Content-Type")
  end

  it "includes HMAC signing when secret present" do
    el = { "config" => { "url" => "ctx[:url]", "secretExpression" => "ctx[:secret]" } }
    code = described_class.new(el, {}).generate
    expect(code).to include("HMAC")
    expect(code).to include("X-Signature")
  end
end
```

```ruby
# spec/services/code_generators/step_actions/notify_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::StepActions::NotifyGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates slack notification" do
    el = { "config" => { "channel" => "slack" } }
    expect(described_class.new(el, {}).generate).to include("SlackNotifier")
  end

  it "generates sms notification" do
    el = { "config" => { "channel" => "sms" } }
    expect(described_class.new(el, {}).generate).to include("SmsService")
  end

  it "defaults to email (sets notification_sent)" do
    expect(described_class.new(element, context).generate).to include("notification_sent")
  end
end
```

- [ ] **Step 3: Run specs**

Run: `bundle exec rspec spec/services/code_generators/step_actions/api_call_generator_spec.rb spec/services/code_generators/step_actions/send_email_generator_spec.rb spec/services/code_generators/step_actions/send_webhook_generator_spec.rb spec/services/code_generators/step_actions/notify_generator_spec.rb -fd`
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add app/services/code_generators/step_actions/api_call_generator.rb \
        app/services/code_generators/step_actions/send_email_generator.rb \
        app/services/code_generators/step_actions/send_webhook_generator.rb \
        app/services/code_generators/step_actions/notify_generator.rb \
        spec/services/code_generators/step_actions/api_call_generator_spec.rb \
        spec/services/code_generators/step_actions/send_email_generator_spec.rb \
        spec/services/code_generators/step_actions/send_webhook_generator_spec.rb \
        spec/services/code_generators/step_actions/notify_generator_spec.rb
git commit -m "feat: add 4 communication step action generators"
```
