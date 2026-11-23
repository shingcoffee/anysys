# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::FileOperations::UploadFileGenerator do
  let(:context) { {} }
  let(:base) { described_class.sample_input }
  let(:element) { { "config" => base } }

  it_behaves_like "a code generator"

  def generate(config = base, generator_context = context)
    described_class.new({ "config" => config }, generator_context)
  end

  def execute(config, ctx)
    CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
  end

  def lint!(config)
    instance = generate(config)
    result = CodeGenerators::BodyLint.check(instance.generate_body, outputs: [instance.value(:resultVar)])
    expect(result.ok?).to be(true), result.violations.inspect
  end

  it "has only required errors on schema defaults" do
    schema = described_class._config_schema
    unexpected = generate(schema.defaults).validate_config(schema.defaults)
                                          .reject { |error| error.respond_to?(:code) && error.code == :required }
    expect(unexpected).to eq([])
  end

  it "accepts sample_input and compiles" do
    expect(generate(base).validate_config(base)).to eq([])
    expect { RubyVM::InstructionSequence.compile(generate(base).generate_step_method) }.not_to raise_error
    lint!(base)
  end

  it "is version 6.1.0" do
    expect(described_class._metadata[:version]).to eq("6.1.0")
  end

  it "picks a record field instead of naming an attachment" do
    expect(described_class._config_schema.fields.map(&:name))
      .to eq(%w[modelVariable fileField sourceVariable filename saveRecord resultVar])
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"upload_file.failed",
          FlowchartRuntime::FileUpload::Error,
          FlowchartRuntime::Template::Error
        ) do
          uploaded = FlowchartRuntime::FileUpload.attach(
            ctx,
            ctx[:model],
            "contract",
            ctx[:invoice_file],
            filename: FlowchartRuntime::Template.render("invoice-{{ order.number }}.pdf", ctx)
          )
          next false unless uploaded
          ctx[:uploaded_file] = uploaded
        end
      end
    RUBY
  end

  it "only stages the file when saveRecord is off" do
    expect(generate(base.merge("saveRecord" => false, "filename" => "")).generate_body)
      .to include('FlowchartRuntime::FileUpload.attach(ctx, ctx[:model], "contract", ctx[:invoice_file], save: false)')
  end

  context "with the page's entity" do
    let(:entity) do
      build(:entity, name: "Order", property_schema: [
        { "name" => "Title", "name_slug" => "title", "type" => "Types::String", "html_type" => "text" },
        { "name" => "Contract", "name_slug" => "contract", "type" => "Types::String", "html_type" => "file" }
      ].to_json)
    end

    def errors_for(config)
      generate(config, { bound_entity: entity }).validate_config(config)
    end

    it "accepts its File field and refuses any other attribute" do
      expect(errors_for(base)).to eq([])
      expect(errors_for(base.merge("fileField" => "title")).map(&:code)).to eq([:not_file_attribute])
      expect(errors_for(base.merge("fileField" => "missing")).map(&:code)).to eq([:unknown_attribute])
    end

    it "does not check a field on a record read from another variable" do
      expect(errors_for(base.merge("modelVariable" => "order", "fileField" => "title"))).to eq([])
    end
  end

  it "stores the file on the record and writes its metadata" do
    customer = create(:customer)
    entity = create(:entity, customer: customer, property_schema: [
      { "name" => "Contract", "name_slug" => "contract", "type" => "Types::String", "html_type" => "file" }
    ].to_json)
    record = EntityEntry.build_for(entity).create!(customer_id: customer.id)

    result = execute(base.merge("filename" => "{{ number }}.pdf"),
                     { model: record, number: "INV-7", invoice_file: { "content" => "%PDF-1.4\n" },
                       customer_id: customer.id, bound_entity: entity, audience: "admin" })

    expect(result[:outcome]).to be_truthy
    expect(result[:ctx][:uploaded_file]).to include("filename" => "INV-7.pdf", "content_type" => "application/pdf")
    expect(EntityEntry.build_for(entity).find(record.id).contract.filename.to_s).to eq("INV-7.pdf")
  end

  it "fails the step when the record is in another tenant" do
    customer = create(:customer)
    entity = create(:entity, customer: customer, property_schema: [
      { "name" => "Contract", "name_slug" => "contract", "type" => "Types::String", "html_type" => "file" }
    ].to_json)
    record = EntityEntry.build_for(entity).create!(customer_id: customer.id)

    result = execute(base, { model: record, invoice_file: "bytes", customer_id: customer.id + 1 })

    expect(result[:outcome]).to be(false)
    expect(result[:ctx][:errors].join).to match(/upload/i)
  end
end
