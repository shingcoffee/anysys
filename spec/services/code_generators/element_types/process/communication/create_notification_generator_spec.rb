# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Communication::CreateNotificationGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  def generate(config = described_class.sample_input)
    described_class.new({ "config" => config }, {}).generate_body
  end

  def errors(config)
    described_class.new({ "config" => config }, {}).validate_config(config)
  end

  def execute(config, ctx)
    CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
  end

  it "has only :required errors for schema defaults" do
    unexpected = errors(described_class._config_schema.defaults).reject { |error| error.code == :required }
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
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"create_notification.failed",
          FlowchartRuntime::Notifications::Error
        ) do
          FlowchartRuntime::Notifications.create(
            ctx,
            recipient: [ctx[:current_user_id]],
            title: {"en" => "Notice"},
            body: {"en" => "Your request was received."}
          )
        end
      end
    RUBY
  end

  it "emits additional recipient context paths and a page id" do
    expect(generated_step(described_class.sample_input.merge("recipients" => %w[admin_id owner.id], "page" => 9))).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"create_notification.failed",
          FlowchartRuntime::Notifications::Error
        ) do
          FlowchartRuntime::Notifications.create(
            ctx,
            recipient: [
              ctx[:current_user_id],
              ctx[:admin_id],
              FlowchartRuntime::Step.dig(ctx[:owner], :id)
            ],
            title: {"en" => "Notice"},
            body: {"en" => "Your request was received."},
            page_id: "9"
          )
        end
      end
    RUBY
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let(:other) { create(:customer) }
    let(:user) { create(:user, :member, customer: customer) }

    it "creates a notification for the current user" do
      ctx = { customer_id: customer.id, current_user_id: user.id, errors: [] }
      result = execute(described_class.sample_input, ctx)
      expect(result[:validation_errors]).to eq([])
      expect(result[:outcome]).to be(true)
      row = FlowchartNotification.find_by!(customer_id: customer.id, user_id: user.id)
      expect(row.title).to eq("en" => "Notice")
      expect(row.body).to eq("en" => "Your request was received.")
    end

    it "fails with a translated message when the recipient is another tenant's user" do
      stranger = create(:user, :member, customer: other)
      ctx = { customer_id: customer.id, current_user_id: stranger.id, errors: [] }
      result = execute(described_class.sample_input, ctx)
      expect(result[:outcome]).to be(false)
      expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.create_notification.recipient_not_found"))
      expect(FlowchartNotification.where(customer_id: customer.id)).to be_empty
    end

    it "notifies additional same-customer recipients" do
      other_user = create(:user, :member, customer: customer)
      ctx = { customer_id: customer.id, current_user_id: user.id, admin_id: other_user.id, errors: [] }
      result = execute(described_class.sample_input.merge("recipients" => ["admin_id"]), ctx)
      expect(result[:outcome]).to be(true)
      expect(FlowchartNotification.where(customer_id: customer.id).pluck(:user_id)).to contain_exactly(user.id, other_user.id)
    end

    def create_page(**attrs)
      allow_any_instance_of(Page).to receive(:bind_default_flowchart)
      create(:page, **attrs)
    end

    it "stores a launched same-customer page id" do
      page = create_page(customer: customer, launched: true)
      ctx = { customer_id: customer.id, current_user_id: user.id, errors: [] }
      result = execute(described_class.sample_input.merge("page" => page.id), ctx)
      expect(result[:outcome]).to be(true)
      expect(FlowchartNotification.find_by!(customer_id: customer.id, user_id: user.id).page_id).to eq(page.id)
    end

    it "fails when the page is not a launched page of this customer" do
      foreign = create_page(customer: other, launched: true)
      ctx = { customer_id: customer.id, current_user_id: user.id, errors: [] }
      result = execute(described_class.sample_input.merge("page" => foreign.id), ctx)
      expect(result[:outcome]).to be(false)
      expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.create_notification.page_not_found"))
      expect(FlowchartNotification.where(customer_id: customer.id)).to be_empty
    end

    it "notifies a duplicated recipient only once" do
      ctx = { customer_id: customer.id, current_user_id: user.id, admin_id: user.id, errors: [] }
      result = execute(described_class.sample_input.merge("recipients" => ["admin_id"]), ctx)
      expect(result[:outcome]).to be(true)
      expect(FlowchartNotification.where(customer_id: customer.id, user_id: user.id).count).to eq(1)
    end
  end
end
