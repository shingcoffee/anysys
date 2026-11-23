# Part 7: Step Action Generators — Security, Background, File, Realtime, Response

## Task 14: Security + Background Generators (3 files)

**Files:**
- Create: `app/services/code_generators/step_actions/authorize_generator.rb`
- Create: `app/services/code_generators/step_actions/enqueue_job_generator.rb`
- Create: `app/services/code_generators/step_actions/schedule_job_generator.rb`
- Test: one spec per generator

**Source references:** `activity_generator/security_steps.rb`, `activity_generator/background_steps.rb`

- [ ] **Step 1: Create all 3 generators**

```ruby
# app/services/code_generators/step_actions/authorize_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module StepActions
    class AuthorizeGenerator < BaseGenerator
      generator_metadata do
        description "Checks authorization (role, policy, or custom expression)"
        category :security
        version "1.0.0"
      end

      input_schema  :current_user
      output_schema # none (raises on failure)

      def generate
        auth_type = config["authType"] || "role_check"
        user = config["userExpression"] || "ctx[:current_user]"
        failure_msg = config["failureMessage"] || "Unauthorized"

        case auth_type
        when "role_check"
          role = config["roleName"] || "admin"
          <<~RUBY.chomp
            raise "#{failure_msg}" unless #{user}.role == "#{role}"
            true
          RUBY
        when "policy_check"
          policy = config["policyClass"] || "ApplicationPolicy"
          action = config["policyAction"] || "show?"
          record = config["recordExpression"] || "ctx[:model]"
          <<~RUBY.chomp
            Pundit.authorize(#{user}, #{record}, :#{action})
            true
          RUBY
        when "custom"
          expression = config["customExpression"] || "true"
          <<~RUBY.chomp
            raise "#{failure_msg}" unless #{expression}
            true
          RUBY
        else
          <<~RUBY.chomp
            raise "#{failure_msg}" unless #{user}.present?
            true
          RUBY
        end
      end

      def validate_config(cfg)
        []
      end

      def example_output
        "raise \"Unauthorized\" unless ctx[:current_user].role == \"admin\"\ntrue"
      end
    end
  end
end
```

```ruby
# app/services/code_generators/step_actions/enqueue_job_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module StepActions
    class EnqueueJobGenerator < BaseGenerator
      generator_metadata do
        description "Enqueues an ActiveJob for background processing"
        category :background
        version "1.0.0"
      end

      input_schema  # varies by job
      output_schema # none (async)

      def generate
        job_class = config["jobClass"] || "ApplicationJob"
        job_args = config["jobArgs"]
        queue = config["queueName"] || "default"
        priority = config["priority"]

        set_opts = ["queue: \"#{queue}\""]
        set_opts << "priority: #{priority}" if priority.present?

        args_part = job_args.present? ? "(#{job_args})" : ""

        <<~RUBY.chomp
          #{job_class}.set(#{set_opts.join(", ")}).perform_later#{args_part}
          true
        RUBY
      end

      def validate_config(cfg)
        errors = []
        errors << "Job class is required" if cfg["jobClass"].blank?
        errors
      end

      def example_output
        "ApplicationJob.set(queue: \"default\").perform_later\ntrue"
      end
    end
  end
end
```

```ruby
# app/services/code_generators/step_actions/schedule_job_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module StepActions
    class ScheduleJobGenerator < BaseGenerator
      generator_metadata do
        description "Schedules a job to run after a delay or at a specific time"
        category :background
        version "1.0.0"
      end

      input_schema  # varies by job
      output_schema # none (async)

      def generate
        job_class = config["jobClass"] || "ApplicationJob"
        job_args = config["jobArgs"]
        delay_type = config["delayType"] || "duration"

        args_part = job_args.present? ? "(#{job_args})" : ""

        wait_part = if delay_type == "atTime"
          scheduled = config["scheduledAt"] || "1.hour.from_now"
          "wait_until: #{scheduled}"
        else
          value = config["delayValue"] || 30
          unit = config["delayUnit"] || "minutes"
          "wait: #{value}.#{unit}"
        end

        <<~RUBY.chomp
          #{job_class}.set(#{wait_part}).perform_later#{args_part}
          true
        RUBY
      end

      def validate_config(cfg)
        errors = []
        errors << "Job class is required" if cfg["jobClass"].blank?
        errors
      end

      def example_output
        "ApplicationJob.set(wait: 30.minutes).perform_later\ntrue"
      end
    end
  end
end
```

- [ ] **Step 2: Write specs**

```ruby
# spec/services/code_generators/step_actions/authorize_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::StepActions::AuthorizeGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "defaults to role_check" do
    expect(described_class.new(element, context).generate).to include('role == "admin"')
  end

  it "generates policy_check" do
    el = { "config" => { "authType" => "policy_check", "policyClass" => "UserPolicy" } }
    expect(described_class.new(el, {}).generate).to include("Pundit.authorize")
  end

  it "generates custom expression check" do
    el = { "config" => { "authType" => "custom", "customExpression" => "ctx[:admin?]" } }
    expect(described_class.new(el, {}).generate).to include("ctx[:admin?]")
  end
end
```

```ruby
# spec/services/code_generators/step_actions/enqueue_job_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::StepActions::EnqueueJobGenerator do
  let(:element) { { "config" => { "jobClass" => "ExportJob" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates perform_later call" do
    expect(described_class.new(element, context).generate).to include("ExportJob")
    expect(described_class.new(element, context).generate).to include("perform_later")
  end

  it "includes queue name" do
    el = { "config" => { "jobClass" => "ExportJob", "queueName" => "exports" } }
    expect(described_class.new(el, {}).generate).to include('queue: "exports"')
  end

  it "includes priority when set" do
    el = { "config" => { "jobClass" => "ExportJob", "priority" => 10 } }
    expect(described_class.new(el, {}).generate).to include("priority: 10")
  end
end
```

```ruby
# spec/services/code_generators/step_actions/schedule_job_generator_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::StepActions::ScheduleJobGenerator do
  let(:element) { { "config" => { "jobClass" => "ReminderJob" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "defaults to duration-based delay" do
    code = described_class.new(element, context).generate
    expect(code).to include("wait: 30.minutes")
  end

  it "supports atTime scheduling" do
    el = { "config" => { "jobClass" => "ReportJob", "delayType" => "atTime", "scheduledAt" => "1.day.from_now" } }
    expect(described_class.new(el, {}).generate).to include("wait_until: 1.day.from_now")
  end
end
```

- [ ] **Step 3: Run specs and commit**

Run: `bundle exec rspec spec/services/code_generators/step_actions/authorize_generator_spec.rb spec/services/code_generators/step_actions/enqueue_job_generator_spec.rb spec/services/code_generators/step_actions/schedule_job_generator_spec.rb -fd`
Expected: All PASS

```bash
git add app/services/code_generators/step_actions/authorize_generator.rb \
        app/services/code_generators/step_actions/enqueue_job_generator.rb \
        app/services/code_generators/step_actions/schedule_job_generator.rb \
        spec/services/code_generators/step_actions/authorize_generator_spec.rb \
        spec/services/code_generators/step_actions/enqueue_job_generator_spec.rb \
        spec/services/code_generators/step_actions/schedule_job_generator_spec.rb
git commit -m "feat: add security and background step action generators"
```

---

## Task 15: File + Realtime + Response Generators (5 files)

**Files:**
- Create: `app/services/code_generators/step_actions/generate_file_generator.rb`
- Create: `app/services/code_generators/step_actions/upload_file_generator.rb`
- Create: `app/services/code_generators/step_actions/publish_event_generator.rb`
- Create: `app/services/code_generators/step_actions/broadcast_generator.rb`
- Create: `app/services/code_generators/step_actions/render_response_generator.rb`
- Test: one spec per generator

**Source references:** `activity_generator/file_steps.rb`, `activity_generator/realtime_steps.rb`, `activity_generator/response_steps.rb`

- [ ] **Step 1: Create all 5 generators**

```ruby
# app/services/code_generators/step_actions/generate_file_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module StepActions
    class GenerateFileGenerator < BaseGenerator
      generator_metadata do
        description "Generates a file (CSV, PDF, Excel) from data"
        category :file_operations
        version "1.0.0"
      end

      input_schema  :data
      output_schema :generated_file

      def generate
        file_type = config["fileType"] || "csv"
        data = config["dataExpression"] || "ctx[:data]"
        result_var = config["resultVar"] || "generated_file"
        filename = config["filenameTemplate"] || "\"export.#{file_type}\""

        case file_type
        when "csv"  then build_csv_generation(data, result_var, filename)
        when "pdf"  then build_pdf_generation(data, result_var, filename)
        when "excel" then build_excel_generation(data, result_var, filename)
        else "# Unknown file type: #{file_type}\ntrue"
        end
      end

      def validate_config(cfg)
        errors = []
        ft = cfg["fileType"]
        unless ft.blank? || %w[csv pdf excel].include?(ft)
          errors << "Unsupported file type: #{ft}"
        end
        errors
      end

      def example_output
        "require \"csv\"\nctx[:generated_file] = CSV.generate { |csv| ... }\ntrue"
      end

      private

      def build_csv_generation(data, result_var, filename)
        columns = config["columns"] || []

        if columns.any?
          headers_line = columns.map { |c| c["key"].inspect }.join(", ")
          values_line = columns.map { |c| "row[#{c['value']}]" }.join(", ")
          <<~RUBY.chomp
            require "csv"
            ctx[:#{result_var}] = CSV.generate do |csv|
              csv << [#{headers_line}]
              #{data}.each { |row| csv << [#{values_line}] }
            end
            ctx[:#{result_var}_filename] = #{filename}
            true
          RUBY
        else
          <<~RUBY.chomp
            require "csv"
            ctx[:#{result_var}] = CSV.generate do |csv|
              #{data}.each { |row| csv << row.values }
            end
            ctx[:#{result_var}_filename] = #{filename}
            true
          RUBY
        end
      end

      def build_pdf_generation(data, result_var, filename)
        template = config["templateName"] || "default"
        <<~RUBY.chomp
          ctx[:#{result_var}] = PdfGenerator.render(template: "#{template}", data: #{data})
          ctx[:#{result_var}_filename] = #{filename}
          true
        RUBY
      end

      def build_excel_generation(data, result_var, filename)
        columns = config["columns"] || []
        <<~RUBY.chomp
          ctx[:#{result_var}] = ExcelGenerator.generate(data: #{data}, columns: #{columns.inspect})
          ctx[:#{result_var}_filename] = #{filename}
          true
        RUBY
      end
    end
  end
end
```

```ruby
# app/services/code_generators/step_actions/upload_file_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module StepActions
    class UploadFileGenerator < BaseGenerator
      generator_metadata do
        description "Attaches a file to an Active Storage attachment"
        category :file_operations
        version "1.0.0"
      end

      input_schema  :file, :model
      output_schema # attachment on model

      def generate
        attachment = config["attachmentName"] || "file"
        source = config["sourceExpression"] || "ctx[:file]"
        record = config["recordExpression"] || "ctx[:model]"

        <<~RUBY.chomp
          #{record}.#{attachment}.attach(#{source})
          true
        RUBY
      end

      def validate_config(cfg)
        []
      end

      def example_output
        "ctx[:model].file.attach(ctx[:file])\ntrue"
      end
    end
  end
end
```

```ruby
# app/services/code_generators/step_actions/publish_event_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module StepActions
    class PublishEventGenerator < BaseGenerator
      generator_metadata do
        description "Publishes an event via ActiveSupport::Notifications"
        category :realtime
        version "1.0.0"
      end

      input_schema  # varies
      output_schema # none (side effect)

      def generate
        event = config["eventName"] || "app.event"
        payload = config["payloadExpression"] || "{}"

        <<~RUBY.chomp
          ActiveSupport::Notifications.instrument("#{event}", #{payload})
          true
        RUBY
      end

      def validate_config(cfg)
        errors = []
        errors << "Event name is required" if cfg["eventName"].blank?
        errors
      end

      def example_output
        "ActiveSupport::Notifications.instrument(\"app.event\", {})\ntrue"
      end
    end
  end
end
```

```ruby
# app/services/code_generators/step_actions/broadcast_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module StepActions
    class BroadcastGenerator < BaseGenerator
      generator_metadata do
        description "Broadcasts updates via Turbo Streams or Action Cable"
        category :realtime
        version "1.0.0"
      end

      input_schema  :model
      output_schema # none (side effect)

      def generate
        broadcast_type = config["broadcastType"] || "turbo_stream"
        stream = config["streamName"] || "\"updates\""

        if broadcast_type == "action_cable"
          data = config["dataExpression"] || "{}"
          <<~RUBY.chomp
            ActionCable.server.broadcast(#{stream}, #{data})
            true
          RUBY
        else
          action = config["action"] || "append"
          target = config["target"] || "items"
          partial = config["partialName"] || "items/item"
          locals = config["localsExpression"] || "{ item: ctx[:model] }"
          <<~RUBY.chomp
            Turbo::StreamsChannel.broadcast_#{action}_to(#{stream}, target: "#{target}", partial: "#{partial}", locals: #{locals})
            true
          RUBY
        end
      end

      def validate_config(cfg)
        []
      end

      def example_output
        "Turbo::StreamsChannel.broadcast_append_to(\"updates\", target: \"items\", partial: \"items/item\", locals: { item: ctx[:model] })\ntrue"
      end
    end
  end
end
```

```ruby
# app/services/code_generators/step_actions/render_response_generator.rb
# frozen_string_literal: true

module CodeGenerators
  module StepActions
    class RenderResponseGenerator < BaseGenerator
      generator_metadata do
        description "Builds the final response payload (JSON, HTML, redirect)"
        category :response
        version "1.0.0"
      end

      input_schema  :model
      output_schema :response, :http_status, :template, :redirect_url

      def generate
        format = config["responseFormat"] || "json"

        case format
        when "json"
          status = config["statusCode"] || 200
          body = config["jsonBody"] || "{ success: true, data: ctx[:model]&.attributes }"
          <<~RUBY.chomp
            ctx[:response] = #{body}
            ctx[:http_status] = #{status}
            true
          RUBY
        when "html"
          status = config["statusCode"] || 200
          template = config["templateName"] || "show"
          <<~RUBY.chomp
            ctx[:template] = "#{template}"
            ctx[:http_status] = #{status}
            true
          RUBY
        when "redirect"
          url = config["redirectUrl"] || "ctx[:redirect_path]"
          flash_type = config["flashType"] || "none"
          flash_msg = config["flashMessage"] || ""
          flash_code = if flash_type != "none" && flash_msg.present?
            "\nctx[:flash] = { #{flash_type}: #{flash_msg.inspect} }"
          else
            ""
          end
          <<~RUBY.chomp
            ctx[:redirect_url] = #{url}#{flash_code}
            true
          RUBY
        else
          <<~RUBY.chomp
            ctx[:response] = { success: true, data: ctx[:model]&.attributes }
            true
          RUBY
        end
      end

      def validate_config(cfg)
        []
      end

      def example_output
        "ctx[:response] = { success: true, data: ctx[:model]&.attributes }\nctx[:http_status] = 200\ntrue"
      end
    end
  end
end
```

- [ ] **Step 2: Write specs for all 5**

```ruby
# spec/services/code_generators/step_actions/generate_file_generator_spec.rb
require "rails_helper"

RSpec.describe CodeGenerators::StepActions::GenerateFileGenerator do
  let(:element) { { "config" => { "fileType" => "csv" } } }
  let(:context) { {} }
  it_behaves_like "a code generator"

  it("generates CSV code") { expect(described_class.new(element, context).generate).to include("CSV.generate") }
  it("generates PDF code") { expect(described_class.new({ "config" => { "fileType" => "pdf" } }, {}).generate).to include("PdfGenerator") }
  it("generates Excel code") { expect(described_class.new({ "config" => { "fileType" => "excel" } }, {}).generate).to include("ExcelGenerator") }
end
```

```ruby
# spec/services/code_generators/step_actions/upload_file_generator_spec.rb
require "rails_helper"

RSpec.describe CodeGenerators::StepActions::UploadFileGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }
  it_behaves_like "a code generator"

  it("generates attach call") { expect(described_class.new(element, context).generate).to include(".attach(") }
end
```

```ruby
# spec/services/code_generators/step_actions/publish_event_generator_spec.rb
require "rails_helper"

RSpec.describe CodeGenerators::StepActions::PublishEventGenerator do
  let(:element) { { "config" => { "eventName" => "user.created" } } }
  let(:context) { {} }
  it_behaves_like "a code generator"

  it("generates instrument call") { expect(described_class.new(element, context).generate).to include("instrument(\"user.created\"") }
end
```

```ruby
# spec/services/code_generators/step_actions/broadcast_generator_spec.rb
require "rails_helper"

RSpec.describe CodeGenerators::StepActions::BroadcastGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }
  it_behaves_like "a code generator"

  it("defaults to turbo_stream") { expect(described_class.new(element, context).generate).to include("Turbo::StreamsChannel") }
  it("supports action_cable") { expect(described_class.new({ "config" => { "broadcastType" => "action_cable" } }, {}).generate).to include("ActionCable") }
end
```

```ruby
# spec/services/code_generators/step_actions/render_response_generator_spec.rb
require "rails_helper"

RSpec.describe CodeGenerators::StepActions::RenderResponseGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }
  it_behaves_like "a code generator"

  it("defaults to json") { expect(described_class.new(element, context).generate).to include("ctx[:response]") }
  it("supports html") { expect(described_class.new({ "config" => { "responseFormat" => "html" } }, {}).generate).to include("ctx[:template]") }
  it("supports redirect") { expect(described_class.new({ "config" => { "responseFormat" => "redirect" } }, {}).generate).to include("ctx[:redirect_url]") }
end
```

- [ ] **Step 3: Run all step action specs**

Run: `bundle exec rspec spec/services/code_generators/step_actions/ -fd`
Expected: All 24 step action generators PASS

- [ ] **Step 4: Verify registry discovers all generators**

Run: `bundle exec rails runner "puts CodeGenerators::GeneratorRegistry.instance.all_generators.keys.sort"`
Expected: Lists all 31 generator names (7 element types + 24 step actions + aliases)

- [ ] **Step 5: Commit**

```bash
git add app/services/code_generators/step_actions/generate_file_generator.rb \
        app/services/code_generators/step_actions/upload_file_generator.rb \
        app/services/code_generators/step_actions/publish_event_generator.rb \
        app/services/code_generators/step_actions/broadcast_generator.rb \
        app/services/code_generators/step_actions/render_response_generator.rb \
        spec/services/code_generators/step_actions/generate_file_generator_spec.rb \
        spec/services/code_generators/step_actions/upload_file_generator_spec.rb \
        spec/services/code_generators/step_actions/publish_event_generator_spec.rb \
        spec/services/code_generators/step_actions/broadcast_generator_spec.rb \
        spec/services/code_generators/step_actions/render_response_generator_spec.rb
git commit -m "feat: add file, realtime, and response step action generators"
```

- [ ] **Step 6: Run full code_generators test suite**

Run: `bundle exec rspec spec/services/code_generators/ -fd`
Expected: All tests PASS (infrastructure + shared + registry + validator + 7 element types + 24 step actions)
