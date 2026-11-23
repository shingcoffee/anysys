# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Background::EnqueueJobGenerator do
  let(:context) { {} }
  let(:base) { described_class.sample_input }
  let(:element) { { "config" => base } }

  it_behaves_like "a code generator"

  def generate(config = base)
    described_class.new({ "config" => config }, context)
  end

  def body(config = base)
    generate(config).generate_body
  end

  def execute(config, ctx)
    CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
  end

  def lint!(config)
    instance = generate(config)
    result = CodeGenerators::BodyLint.check(instance.generate_body, outputs: [instance.value(:resultVar)])
    expect(result.ok?).to be(true), result.violations.inspect
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"enqueue_job.failed",
          FlowchartRuntime::JobSchedule::Error,
          FlowchartRuntime::Schedule::Error,
          FlowchartRuntime::Invocable::Error
        ) do
          ctx[:enqueued_job_id] = FlowchartRuntime::JobSchedule.run(
            FlowchartRuntime::Invocable.job!("ApplicationJob"),
            schedule_when: "now",
            args: [ctx[:user_id]],
            queue: "default"
          )
          true
        end
      end
    RUBY
  end

  it "is version 4.1.0" do
    expect(described_class._metadata[:version]).to eq("4.1.0")
  end

  it "emits run_at for when at" do
    code = generated_step(described_class.sample_input.merge("when" => "at", "runAt" => "1.hour.from_now"))
    expect(code).to include('schedule_when: "at"')
    expect(code).to include("run_at: 1.hour.from_now")
    expect(code).not_to include("wait_seconds:")
  end

  it "emits wait_seconds for when after" do
    code = generated_step(described_class.sample_input.merge("when" => "after", "waitSeconds" => 60))
    expect(code).to include("wait_seconds: 60")
  end

  it "emits cron and timezone for recurring without interval kwargs" do
    code = generated_step(described_class.sample_input.merge("when" => "recurring", "cronExpression" => "0 * * * *"))
    expect(code).to include('cron_expression: "0 * * * *"')
    expect(code).to include('timezone: "UTC"')
    expect(code).not_to include("interval_seconds:")
    expect(code).not_to include("recurrence_limit:")
  end

  it "emits interval kwargs for recurring without cron" do
    code = generated_step(
      described_class.sample_input.merge(
        "when" => "recurring",
        "cronExpression" => "",
        "intervalSeconds" => 120,
        "recurrenceLimit" => 3
      )
    )
    expect(code).to include("interval_seconds: 120")
    expect(code).to include("recurrence_limit: 3")
    expect(code).not_to include("cron_expression:")
  end

  it "has only required errors on schema defaults" do
    schema = described_class._config_schema
    unexpected = generate(schema.defaults).validate_config(schema.defaults)
                                          .reject { |error| error.respond_to?(:code) && error.code == :required }
    expect(unexpected).to eq([])
  end

  described_class::WHEN_MODES.each do |mode|
    it "emits a BodyLint-clean JobSchedule.run body for when #{mode}" do
      extra = case mode
      when "at" then { "runAt" => "1.hour.from_now" }
      when "after" then { "waitSeconds" => 60 }
      when "recurring" then { "cronExpression" => "0 * * * *" }
      else {}
      end
      config = base.merge("when" => mode).merge(extra)
      expect(generate(config).validate_config(config)).to eq([])
      expect(body(config)).to include("FlowchartRuntime::JobSchedule.run")
      expect(body(config)).to include(%(schedule_when: "#{mode}"))
      expect(body(config)).not_to include("ctx[:_last_error]")
      lint!(config)
    end
  end

  it "enqueues now and records the job id" do
    job = instance_double(ActiveJob::Base, job_id: "job-1", successfully_enqueued?: true)
    configured = double("configured", perform_later: job)
    job_class = double("ApplicationJob", set: configured, perform_later: job)
    allow(FlowchartRuntime::Invocable).to receive(:job!).with("ApplicationJob").and_return(job_class)
    allow(job_class).to receive(:respond_to?).and_return(true)

    result = execute(base.merge("when" => "now", "jobArgs" => ""), { user_id: 7 })
    expect(result[:outcome]).to be(true)
    expect(result[:ctx][:enqueued_job_id]).to eq("job-1")
  end

  it "fails through Step.attempt when enqueue is refused" do
    configured = double("configured", perform_later: false)
    job_class = double("ApplicationJob", set: configured, perform_later: false)
    allow(FlowchartRuntime::Invocable).to receive(:job!).and_return(job_class)
    allow(job_class).to receive(:respond_to?).and_return(true)

    result = execute(base.merge("when" => "now", "jobArgs" => ""), {})
    expect(result[:outcome]).to be(false)
    expect(result[:ctx][:errors].join).to match(/enqueue|job/i)
    expect(result[:ctx]).not_to have_key(:_last_error)
  end

  it "fails through Step.attempt when the job class is not allow-listed" do
    allow(FlowchartRuntime::Invocable).to receive(:job!)
      .and_raise(FlowchartRuntime::Invocable::Error, "job not allowlisted: MissingJob")

    result = execute(base.merge("when" => "now", "jobArgs" => ""), {})
    expect(result[:outcome]).to be(false)
    expect(result[:ctx][:errors].join).to match(/enqueue|job/i)
  end
end
