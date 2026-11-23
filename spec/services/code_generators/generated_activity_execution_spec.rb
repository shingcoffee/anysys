# frozen_string_literal: true

require "rails_helper"

RSpec.describe "generated flowchart activity execution" do
  def execute(generator_class, config: nil, ctx: {}, context: {})
    CodeGenerators::TestRunner.execute(
      generator_class,
      config: config || generator_class.sample_input,
      context: context,
      ctx: ctx
    )
  end

  # --- Registry-wide syntax coverage -----------------------------------------

  CodeGenerators::GeneratorRegistry.all.each do |generator_class|
    it "compiles #{generator_class.name} sample source" do
      result = CodeGenerators::TestRunner.run(
        generator_class,
        config: generator_class.sample_input
      )

      expect(result.fetch(:validation_errors)).to be_empty
      code = result.fetch(:code)
      next if code.nil? # start / subflow structural shells

      expect {
        RubyVM::InstructionSequence.compile(code)
      }.not_to raise_error
    end
  end

  # --- Representative success + operational failure per facade category ------

  describe "HTTP (api_call)" do
    let(:generator) { CodeGenerators::ElementTypes::Process::Communication::ApiCallGenerator }
    let(:config) { generator.sample_input }

    it "succeeds when OutboundHttp returns a success JSON body" do
      allow(OutboundHttp).to receive(:request)
        .and_return(OutboundHttp::Response.new(status: 200, headers: {}, body: '{"ok":true}'))

      result = execute(generator, config: config, ctx: {})
      expect(result.fetch(:outcome)).to eq(ok: true)
      expect(result.fetch(:ctx)[:api_response]).to eq(ok: true)
    end

    it "fails closed on OutboundHttp transport errors" do
      allow(OutboundHttp).to receive(:request)
        .and_raise(OutboundHttp::TransportError, "connection refused")

      result = execute(generator, config: config, ctx: {})
      expect(result.fetch(:outcome)).to eq(false)
      expect(result.fetch(:ctx)[:error_details]).to include(
        hash_including("code" => "transport_error")
      )
      expect(result.fetch(:ctx)).not_to have_key(:_last_error)
    end
  end

  describe "crypto (encrypt_data)" do
    let(:generator) { CodeGenerators::ElementTypes::Process::Security::EncryptDataGenerator }
    let(:config) do
      generator.sample_input.merge(
        "keySource" => "ctx",
        "keyPath" => "encryption_key",
        "sourceVariable" => "sensitive_data",
        "resultVar" => "encrypted"
      )
    end
    let(:key) { "0" * 32 }

    it "succeeds when Cipher.encrypt_value returns ciphertext" do
      allow(FlowchartRuntime::Cipher).to receive(:resolve_key).and_yield.and_return(key)
      allow(FlowchartRuntime::Cipher).to receive(:encrypt_value).and_return("ENCODED")

      result = execute(generator, config: config, ctx: { sensitive_data: "secret", encryption_key: key })
      expect(result.fetch(:outcome)).to eq(true)
      expect(result.fetch(:ctx)[:encrypted]).to eq("ENCODED")
    end

    it "fails closed on Cipher::Error" do
      allow(FlowchartRuntime::Cipher).to receive(:resolve_key).and_yield.and_return(key)
      allow(FlowchartRuntime::Cipher).to receive(:encrypt_value)
        .and_raise(FlowchartRuntime::Cipher::Error, "bad key")

      result = execute(generator, config: config, ctx: { sensitive_data: "secret", encryption_key: key })
      expect(result.fetch(:outcome)).to eq(false)
      expect(result.fetch(:ctx)[:errors].join).to include("Could not encrypt")
    end
  end

  describe "archive/file (decompress_files)" do
    let(:generator) { CodeGenerators::ElementTypes::Process::FileOperations::DecompressFilesGenerator }
    let(:config) { generator.sample_input.merge("format" => "zip") }

    it "succeeds when Archive.unpack returns entries" do
      allow(FlowchartRuntime::Archive).to receive(:unpack)
        .and_return([{ "filename" => "a.txt", "content" => "hello", "content_type" => "text/plain" }])

      result = execute(generator, config: config, ctx: { archive: "PK\x03\x04fake" })
      expect(result.fetch(:outcome)).to be_truthy
      expect(result.fetch(:ctx)[:extracted]).to eq(
        [{ "filename" => "a.txt", "content" => "hello", "content_type" => "text/plain" }]
      )
    end

    it "fails closed on Archive::Error" do
      allow(FlowchartRuntime::Archive).to receive(:unpack)
        .and_raise(FlowchartRuntime::Archive::Error, "corrupt archive")

      result = execute(generator, config: config, ctx: { archive: "not-an-archive" })
      expect(result.fetch(:outcome)).to be(false)
      expect(result.fetch(:ctx)[:errors].join).to match(/decompress|archive/i)
      expect(result.fetch(:ctx)).not_to have_key(:_last_error)
    end
  end

  describe "model/data (assign_value + query_models)" do
    it "assign_value succeeds for integer sample" do
      generator = CodeGenerators::ElementTypes::Process::DataOperations::AssignValueGenerator
      result = execute(
        generator,
        config: { "resultVar" => "count", "valueType" => "integer", "integerValue" => 42 },
        ctx: {}
      )
      expect(result.fetch(:outcome)).to eq(true)
      expect(result.fetch(:ctx)[:count]).to eq(42)
    end

    # The emitted body passes Entries.query only the kwargs that differ from
    # its defaults, so the double records exactly those.
    def stub_entries_query(result: nil, error: nil)
      if error
        allow(FlowchartRuntime::Entries).to receive(:query).and_raise(error)
      else
        allow(FlowchartRuntime::Entries).to receive(:query).and_return(result)
      end
    end

    it "query_models succeeds when Entries.query returns records" do
      generator = CodeGenerators::ElementTypes::Process::ModelOperations::QueryModelsGenerator
      entity = instance_double(Entity)
      query_result = FlowchartRuntime::Entries::QueryResult.new(
        records: [{ id: 1 }],
        pagination: { total_count: 3, page: 1, per_page: 25, total_pages: 1, has_next: false }
      )
      stub_entries_query(result: query_result)
      config = generator.sample_input.merge("pageSize" => 25, "orderBy" => "created_at")

      result = execute(generator, config: config, ctx: { bound_entity: entity, customer_id: 1, page: 1 })

      expect(result.fetch(:outcome)).to eq([{ id: 1 }])
      expect(result.fetch(:ctx)[:models]).to eq([{ id: 1 }])
      expect(result.fetch(:ctx)[:pagination])
        .to eq(total_count: 3, page: 1, per_page: 25, total_pages: 1, has_next: false)
      expect(FlowchartRuntime::Entries).to have_received(:query).with(
        hash_including(bound_entity: entity, customer_id: 1, page: 1),
        order_by: "created_at", page: 1, per_page: 25
      )
    end

    it "query_models orders by the configured direction rather than a fixed one" do
      generator = CodeGenerators::ElementTypes::Process::ModelOperations::QueryModelsGenerator
      entity = instance_double(Entity)
      stub_entries_query(result: FlowchartRuntime::Entries::QueryResult.new(records: [], pagination: nil))
      config = generator.sample_input.merge("orderBy" => "updated_at", "orderDirection" => "desc")

      result = execute(generator, config: config, ctx: { bound_entity: entity, customer_id: 1 })

      expect(result.fetch(:outcome)).to eq([])
      expect(FlowchartRuntime::Entries).to have_received(:query).with(
        anything, order_by: "updated_at", order_direction: "desc"
      )
    end

    it "query_models fails explicitly when Entries.query raises" do
      generator = CodeGenerators::ElementTypes::Process::ModelOperations::QueryModelsGenerator
      entity = instance_double(Entity)
      stub_entries_query(error: StandardError.new("db down"))

      expect {
        execute(generator, config: generator.sample_input, ctx: { bound_entity: entity, customer_id: 1 })
      }.to raise_error(StandardError, /db down/)

      expect(FlowchartRuntime::Entries).to have_received(:query)
    end
  end

  describe "cache/lock (cache_read + acquire_lock)" do
    it "cache_read succeeds when Rails.cache hits" do
      generator = CodeGenerators::ElementTypes::Process::Caching::CacheReadGenerator
      allow(Rails.cache).to receive(:read).and_return({ id: 7 })

      result = execute(generator, ctx: { customer_id: 1 })
      expect(result.fetch(:outcome)).to be_truthy
      expect(result.fetch(:ctx)[:cached]).to eq({ id: 7 })
    end

    it "fails with a translated message when the tenant is unknown" do
      generator = CodeGenerators::ElementTypes::Process::Caching::CacheReadGenerator
      allow(Rails.cache).to receive(:read).and_return({ id: 7 })

      result = execute(generator, ctx: {})
      expect(result.fetch(:outcome)).to eq(false)
      expect(result.fetch(:ctx)[:errors].first).to include("Could not read the cache")
    end

    it "acquire_lock succeeds when Lock.acquire returns true" do
      generator = CodeGenerators::ElementTypes::Process::Concurrency::AcquireLockGenerator
      allow(FlowchartRuntime::Lock).to receive(:acquire).and_return(true)

      result = execute(generator, config: generator.sample_input, ctx: { customer_id: 1 })
      expect(result.fetch(:outcome)).to be_truthy
      expect(result.fetch(:ctx)[:_cache_lock_key]).to eq("order:")
      expect(result.fetch(:ctx)[:_lock_token]).to be_present
    end

    it "acquire_lock fails closed when Lock.acquire returns false" do
      generator = CodeGenerators::ElementTypes::Process::Concurrency::AcquireLockGenerator
      allow(FlowchartRuntime::Lock).to receive(:acquire).and_return(false)

      result = execute(generator, config: generator.sample_input, ctx: { customer_id: 1 })
      expect(result.fetch(:outcome)).to eq(false)
    end
  end


  describe "jobs (enqueue_job)" do
    let(:generator) { CodeGenerators::ElementTypes::Process::Background::EnqueueJobGenerator }
    let(:job_class) do
      Class.new(ApplicationJob) do
        def self.name = "GeneratedActivityExecutionJob"
        def perform(*) = true
      end
    end

    before do
      stub_const("GeneratedActivityExecutionJob", job_class)
      allow(FlowchartRuntime::Invocable).to receive(:job!).with("ApplicationJob").and_return(job_class)
      allow(FlowchartRuntime::Invocable).to receive(:job!).with("MissingJob")
        .and_raise(FlowchartRuntime::Invocable::Error, "job not found: MissingJob")
    end

    it "succeeds when Invocable.job! resolves and perform_later is called" do
      relation = double("JobSet", perform_later: true)
      allow(job_class).to receive(:set).and_return(relation)

      result = execute(
        generator,
        config: generator.sample_input.merge("jobClass" => "ApplicationJob", "jobArgs" => "", "when" => "now"),
        ctx: { user_id: 9 }
      )
      expect(result.fetch(:outcome)).to eq(true)
      expect(job_class).to have_received(:set)
    end

    it "fails closed when Invocable.job! rejects the class" do
      result = execute(
        generator,
        config: generator.sample_input.merge("jobClass" => "MissingJob", "jobArgs" => "", "when" => "now"),
        ctx: {}
      )
      expect(result.fetch(:outcome)).to eq(false)
      expect(result.fetch(:ctx)[:errors].join).to match(/enqueue|job/i)
      expect(result.fetch(:ctx)).not_to have_key(:_last_error)
    end
  end

  describe "response (render_response)" do
    it "is no longer a registered step action" do
      expect(CodeGenerators::GeneratorRegistry.find_step_action("render_response")).to be_nil
      expect(defined?(CodeGenerators::ElementTypes::Process::Response::RenderResponseGenerator)).to be_nil
    end
  end

  # --- Invalid configuration must not persist partial activity source --------

  describe "invalid configuration persistence" do
    let_it_be(:customer) { create(:customer) }

    def flowchart_configuration(steps:)
      {
        "elements" => [
          { "id" => "s", "type" => "start", "label" => "Start", "properties" => {} },
          {
            "id" => "p",
            "type" => "process",
            "label" => "Work",
            "properties" => { "steps" => steps }
          },
          { "id" => "e", "type" => "end", "label" => "End", "properties" => {} }
        ],
        "connections" => [
          { "id" => "c1", "from" => "s", "to" => "p" },
          { "id" => "c2", "from" => "p", "to" => "e" }
        ],
        "metadata" => {}
      }
    end

    it "raises ActivityGenerator::Error and does not replace prior activity with a failure stub" do
      valid_steps = [
        {
          "action" => "assign_value",
          "config" => { "resultVar" => "x", "valueType" => "integer", "integerValue" => 1 }
        }
      ]
      flowchart = Flowchart.create!(
        name: "Exec Persist #{SecureRandom.hex(4)}",
        configuration: flowchart_configuration(steps: valid_steps).to_json,
        customer: customer,
        status: :draft
      )
      prior_activity = flowchart.activity
      expect(prior_activity).to be_present
      expect(prior_activity).not_to start_with("# ActivityGenerator failed")

      invalid_steps = [
        { "action" => "assign_value", "config" => { "valueType" => "expression" } } # missing valueExpression
      ]
      flowchart.configuration = flowchart_configuration(steps: invalid_steps).to_json

      expect { flowchart.save! }.to raise_error(ActivityGenerator::Error) { |error|
        expect(error.code).to eq(:invalid_generator_config)
      }

      flowchart.reload
      expect(flowchart.activity).to eq(prior_activity)
      expect(flowchart.activity).not_to include("# ActivityGenerator failed")
    end
  end
end
