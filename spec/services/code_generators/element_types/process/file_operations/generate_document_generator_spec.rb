# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::FileOperations::GenerateDocumentGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  def generate(config = described_class.sample_input)
    described_class.new({ "config" => config }, {}).generate_body
  end

  def errors(config)
    described_class.new({ "config" => config }, {}).validate_config(config)
  end

  def pdf_text(payload)
    payload.to_s.scan(/BT(.*?)ET/m).flat_map do |(block)|
      hex = block.scan(/<([0-9A-Fa-f]+)>/).map { |pair| [pair.first].pack("H*") }
      literals = block.scan(/\((?:\\.|[^\\)])*\)/).map do |token|
        token[1..-2].gsub(/\\n/, "\n").gsub(/\\(.)/, '\\1')
      end
      hex + literals
    end.join
  end

  it "has only :required errors for schema defaults" do
    defaults = described_class._config_schema.defaults
    unexpected = errors(defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "accepts sample_input and compiles" do
    sample = described_class.sample_input
    expect(errors(sample)).to eq([])
    expect { RubyVM::InstructionSequence.compile("def test_step(ctx, **)\n#{generate(sample)}\nend") }.not_to raise_error
  end

  it "is version 1.2.0" do
    expect(described_class._metadata[:version]).to eq("1.2.0")
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~'RUBY'.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"generate_document.failed",
          FlowchartRuntime::Document::Error,
          FlowchartRuntime::Template::Error
        ) do
          ctx[:document] = FlowchartRuntime::Document.pdf(
            title: FlowchartRuntime::Template.render("Invoice {{ name }}", ctx),
            body: FlowchartRuntime::Template.render("Hello {{ name }}\n\n## Details", ctx),
            rows: ctx[:rows],
            customer_id: ctx[:customer_id]
          )
        end
      end
    RUBY
  end

  it "emits distinct source for pageSize, orientation, header, footer and pageNumbers" do
    sample = described_class.sample_input
    expect(generate(sample.merge("pageSize" => "letter"))).not_to eq(generate(sample.merge("pageSize" => "legal")))
    expect(generate(sample.merge("orientation" => "landscape"))).not_to eq(generate)
    expect(generate(sample.merge("header" => "Acme {{ name }}"))).not_to eq(generate)
    expect(generate(sample.merge("footer" => "Confidential"))).not_to eq(generate)
    expect(generate(sample.merge("pageNumbers" => true))).not_to eq(generate)
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let(:other) { create(:customer) }
    let(:config) do
      described_class.sample_input.merge(
        "title" => "Invoice {{ name }}",
        "body" => "Hello {{ name }}\n\n## Items",
        "sourceVariable" => "rows",
        "columns" => [{ "key" => "Item", "value" => "item" }, { "key" => "Qty", "value" => "qty" }],
        "filename" => "invoice.pdf"
      )
    end

    it "stores a PDF blob whose text contains the rendered values" do
      ctx = {
        customer_id: customer.id,
        name: "Ada Lovelace",
        rows: [{ "item" => "Widgets", "qty" => "3" }],
        errors: []
      }
      result = CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
      expect(result[:validation_errors]).to eq([])
      expect(result[:outcome]).to eq(ctx[:document])

      document = ctx[:document]
      expect(document["filename"]).to eq("invoice.pdf")
      expect(document["customer_id"]).to eq(customer.id)
      blob = ActiveStorage::Blob.find(document["blob_id"])
      expect(blob.metadata["customer_id"].to_s).to eq(customer.id.to_s)
      expect(blob.content_type).to eq("application/pdf")
      payload = blob.download
      expect(payload).to start_with("%PDF")
      text = pdf_text(payload)
      expect(text).to include("Ada Lovelace")
      expect(text).to include("Widgets")
      expect(text).to include("3")
      expect(ActiveStorage::Blob.where("id != ?", blob.id).where("metadata LIKE ?", "%#{other.id}%")).to be_empty
    end

    it "renders header, footer and landscape letter pages into the stored PDF" do
      ctx = {
        customer_id: customer.id,
        name: "Ada Lovelace",
        rows: [{ "item" => "Widgets", "qty" => "3" }],
        errors: []
      }
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: config.merge(
          "pageSize" => "letter",
          "orientation" => "landscape",
          "header" => "Acme {{ name }}",
          "footer" => "Confidential",
          "pageNumbers" => true
        ),
        ctx: ctx
      )
      expect(result[:outcome]).to eq(ctx[:document])
      payload = ActiveStorage::Blob.find(ctx[:document]["blob_id"]).download
      expect(payload).to include("/MediaBox")
      expect(payload).to match(/\[0 0 792(\.0)? 612(\.0)?\]/)
      text = pdf_text(payload)
      expect(text).to include("Acme Ada Lovelace")
      expect(text).to include("Confidential")
    end

    it "rejects a template that does not parse before generating code" do
      expect(errors(config.merge("title" => "Invoice {% bogus %}")).map(&:code)).to eq([:invalid_template])
    end

    it "fails the step instead of raising when a template fails to render" do
      allow(FlowchartRuntime::Template).to receive(:render)
        .and_raise(FlowchartRuntime::Template::Error, "Memory limits exceeded")
      ctx = { customer_id: customer.id, name: "Ada", rows: [], errors: [] }
      result = CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)

      expect(result[:outcome]).to be(false)
      expect(ctx[:errors].last).to eq(I18n.t("flowchart_runtime.errors.generate_document.failed", reason: "Error"))
      expect(ActiveStorage::Blob.count).to eq(0)
    end
  end
end
