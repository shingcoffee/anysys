# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Security::RegisterMemberGenerator do
  let(:context) { {} }
  let(:base) { { "personVar" => "model", "resultVar" => "registration" } }
  let(:element) { { "config" => base } }

  it_behaves_like "a code generator"

  def body(config = base)
    described_class.new({ "config" => config }, context).generate_body
  end

  def errors(config)
    described_class.new(element, context).validate_config(config)
  end

  def execute(config, ctx)
    CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
  end

  it "has only :required errors for schema defaults" do
    unexpected = errors(described_class._config_schema.defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        ctx[:registration] = FlowchartRuntime::Registration.call(
          ctx,
          person: ctx[:model],
          identity: ctx[:identity]
        )
      end
    RUBY
  end

  describe "behaviour" do
    let_it_be(:customer) { create(:customer) }
    let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
    let(:entity) do
      enable_module!("authentication", customer).set_extendable_model!(person_model, true)
      create(:entity, customer: customer, name: "Student", extended_model: person_model)
    end
    let(:allow_guard) do
      instance_double(Billing::Quota::Guard::Result, allowed?: true, message: "allowed")
    end

    def enable_signup!
      fm = enable_module!("authentication", customer)
      assignment = FeatureModules::CustomerAssignment.find_by!(
        customer_id: customer.id, feature_module_id: fm.id
      )
      assignment.update!(configuration: { "allow_registration" => true }.to_json)
    end

    before do
      allow(Billing::Quota::Guard).to receive(:check).and_return(allow_guard)
    end

    it "delegates a public person run to the runtime and writes created" do
      enable_signup!
      ctx = {
        audience: "public",
        bound_entity: entity,
        customer_id: customer.id,
        identity: { "first_name" => "Pat", "last_name" => "Lee", "email" => "gen@example.com" },
        errors: []
      }
      ctx[:model] = FlowchartRuntime::Entries.scope(ctx).new(customer_id: customer.id)

      result = execute(base, ctx)
      expect(result[:outcome]).to eq("status" => "created")
      expect(ctx[:registration]).to eq("status" => "created")
      expect(ctx[:submission_outcome]).to eq("preset" => "registration_pending")
    end

    it "reads identity from identityVar" do
      enable_signup!
      ctx = {
        audience: "public",
        bound_entity: entity,
        customer_id: customer.id,
        signup: { "first_name" => "Pat", "last_name" => "Lee", "email" => "idvar@example.com" },
        errors: []
      }
      ctx[:model] = FlowchartRuntime::Entries.scope(ctx).new(customer_id: customer.id)

      result = execute(base.merge("identityVar" => "signup"), ctx)
      expect(result[:outcome]).to eq("status" => "created")
    end

    it "fails with the translated public_only code for a member run" do
      enable_signup!
      ctx = {
        audience: "member",
        bound_entity: entity,
        customer_id: customer.id,
        identity: { "first_name" => "Pat", "last_name" => "Lee", "email" => "mem@example.com" },
        errors: []
      }
      result = execute(base, ctx)
      expect(result[:outcome]).to be(false)
      expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.register_member.public_only"))
    end
  end
end
