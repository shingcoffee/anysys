# frozen_string_literal: true

require "rails_helper"

RSpec.describe DynamicClassLoader do
  # Fresh, throwaway namespace per example so loaded constants never leak.
  let(:namespace) { Module.new }

  describe "#initialize" do
    it "accepts nil entity" do
      loader = described_class.new(nil)
      expect(loader.entity).to be_nil
    end

    it "accepts an entity" do
      entity = build(:entity, name: "User Profile")
      loader = described_class.new(entity)
      expect(loader.entity).to eq(entity)
    end
  end

  describe "#model_class_name" do
    context "with bound entity" do
      it "derives class name from entity name" do
        entity = build(:entity, name: "User Profile")
        loader = described_class.new(entity)
        expect(loader.model_class_name).to eq("UserProfile")
      end

      it "handles multi-word names" do
        entity = build(:entity, name: "Sales Order Item")
        loader = described_class.new(entity)
        expect(loader.model_class_name).to eq("SalesOrderItem")
      end
    end

    context "without bound entity" do
      it "returns BlueprintEntity" do
        loader = described_class.new(nil)
        expect(loader.model_class_name).to eq("BlueprintEntity")
      end
    end
  end

  describe "#contract_class_name" do
    context "with bound entity" do
      it "derives contract name from entity name" do
        entity = build(:entity, name: "User Profile")
        loader = described_class.new(entity)
        expect(loader.contract_class_name).to eq("UserProfileContract")
      end
    end

    context "without bound entity" do
      it "returns BlueprintEntityContract" do
        loader = described_class.new(nil)
        expect(loader.contract_class_name).to eq("BlueprintEntityContract")
      end
    end
  end

  describe "#load_into" do
    context "with nil entity" do
      let(:loader) { described_class.new(nil) }

      it "loads blueprint model class" do
        loader.load_into(namespace)
        expect(namespace.const_defined?(:BlueprintEntity)).to be true
      end

      it "loads blueprint contract class" do
        loader.load_into(namespace)
        expect(namespace.const_defined?(:BlueprintEntityContract)).to be true
      end

      it "blueprint model has expected interface" do
        loader.load_into(namespace)
        model = namespace::BlueprintEntity.new(foo: "bar")

        expect(model).to respond_to(:attributes)
        expect(model).to respond_to(:save)
        expect(model).to respond_to(:destroy)
        expect(model).to respond_to(:persisted?)
        expect(model.attributes).to eq(foo: "bar")
        expect(model.save).to be true
        expect(model.persisted?).to be false
      end

      it "blueprint contract has expected interface" do
        loader.load_into(namespace)
        model = namespace::BlueprintEntity.new
        contract = namespace::BlueprintEntityContract.new(model)

        expect(contract).to respond_to(:model)
        expect(contract).to respond_to(:errors)
        expect(contract).to respond_to(:validate)
        expect(contract).to respond_to(:save)
        expect(contract.validate(name: "test")).to be true
      end

      it "returns class names hash" do
        result = loader.load_into(namespace)
        expect(result).to eq(
          model_class: "BlueprintEntity",
          contract_class: "BlueprintEntityContract"
        )
      end
    end

    context "with entity having property_schema" do
      let(:entity) do
        create(:entity,
          name: "Product",
          property_schema: [
            { "name" => "name", "name_slug" => "name", "type" => "Types::String", "validators" => [{ "type" => "presence" }] },
            { "name" => "price", "name_slug" => "price", "type" => "Types::Float", "validators" => [{ "type" => "numericality" }] }
          ].to_json
        )
      end
      let(:loader) { described_class.new(entity) }

      it "loads the entity model class" do
        loader.load_into(namespace)
        expect(namespace.const_defined?(:Product)).to be true
      end

      it "model class has typed attribute accessors from property_schema" do
        loader.load_into(namespace)
        product = namespace::Product.new(name: "Widget", price: 9.99)

        expect(product.name).to eq("Widget")
        expect(product.price).to eq(9.99)
        expect(product.save).to be true
      end

      it "model class supports attribute assignment" do
        loader.load_into(namespace)
        product = namespace::Product.new
        product.name = "Gadget"
        product.price = 19.99

        expect(product.name).to eq("Gadget")
        expect(product.price).to eq(19.99)
      end

      it "model class supports hash-like access via [] and []=" do
        loader.load_into(namespace)
        product = namespace::Product.new
        product[:name] = "Widget"
        product[:price] = 9.99

        expect(product[:name]).to eq("Widget")
        expect(product[:price]).to eq(9.99)
      end

      it "loads the entity contract class" do
        loader.load_into(namespace)
        expect(namespace.const_defined?(:ProductContract)).to be true
      end

      it "contract inherits from EntityEntryContract (Reform::Form)" do
        loader.load_into(namespace)
        expect(namespace::ProductContract.ancestors).to include(EntityEntryContract)
        expect(namespace::ProductContract.ancestors).to include(Reform::Form)
      end

      it "contract validates and syncs params to model" do
        loader.load_into(namespace)
        model = namespace::Product.new
        contract = namespace::ProductContract.new(model)

        expect(contract.validate("name" => "Widget", "price" => 9.99)).to be true
        expect(contract.name).to eq("Widget")
        expect(contract.price).to eq(9.99)
      end

      it "contract applies validations from property_schema" do
        loader.load_into(namespace)
        model = namespace::Product.new
        contract = namespace::ProductContract.new(model)

        # name is required (presence validator)
        expect(contract.validate("name" => nil, "price" => 9.99)).to be false
        expect(contract.errors[:name]).to be_present
      end

      it "returns class names hash" do
        result = loader.load_into(namespace)
        expect(result).to eq(
          model_class: "Product",
          contract_class: "ProductContract"
        )
      end
    end

    context "with entity having empty property_schema" do
      let(:entity) { create(:entity, name: "Empty", property_schema: [].to_json) }
      let(:loader) { described_class.new(entity) }

      it "loads model class without attribute accessors" do
        loader.load_into(namespace)
        expect(namespace.const_defined?(:Empty)).to be true

        model = namespace::Empty.new
        expect(model).to respond_to(:save)
        expect(model).to respond_to(:destroy)
      end
    end
  end

  describe "#load_into idempotency (const_defined? guard)" do
    it "does not redefine blueprint constants or warn on a second load" do
      loader = described_class.new(nil)
      verbose = $VERBOSE
      $VERBOSE = true
      loader.load_into(namespace)
      klass_before = namespace::BlueprintEntity
      expect { loader.load_into(namespace) }.not_to output.to_stderr
      expect(namespace::BlueprintEntity).to equal(klass_before)
    ensure
      $VERBOSE = verbose
    end

    context "with entity" do
      let(:entity) { create(:entity, name: "Widget") }
      let(:loader) { described_class.new(entity) }

      it "preserves the same constant object on second call (guard hits early return)" do
        loader.load_into(namespace)
        klass_before = namespace::Widget

        loader.load_into(namespace)

        # const_defined? guard fires → same class object returned
        expect(namespace::Widget).to equal(klass_before)
      end
    end
  end

  describe "entity model destroy and persisted? methods" do    let(:entity) do
      create(:entity, name: "Item",
        property_schema: [{ "name" => "title", "name_slug" => "title", "type" => "Types::String" }].to_json)
    end

    it "destroy returns true" do
      described_class.new(entity).load_into(namespace)
      model = namespace::Item.new(title: "x")
      expect(model.destroy).to be true
    end

    it "persisted? returns false" do
      described_class.new(entity).load_into(namespace)
      model = namespace::Item.new(title: "x")
      expect(model.persisted?).to be false
    end
  end

  describe "fallback model when build_entity_model raises" do    let(:entity) { create(:entity, name: "BrokenModel") }

    it "defines a fallback model class and does not raise" do
      loader = described_class.new(entity)
      # Make property_schema_json raise to trigger the rescue path in build_entity_model
      allow(entity).to receive(:property_schema_json).and_raise(StandardError, "schema read failure")

      expect { loader.load_into(namespace) }.not_to raise_error
    end
  end

  describe "fallback contract when build_entity_contract raises" do    let(:entity) { create(:entity, name: "BrokenContract") }

    before do
      allow(EntityEntryContract).to receive(:build_for).and_raise(StandardError, "contract build failed")
    end

    it "defines a fallback contract class without raising" do
      loader = described_class.new(entity)
      expect { loader.load_into(namespace) }.not_to raise_error
    end

    it "the fallback contract has the expected interface" do
      loader = described_class.new(entity)
      loader.load_into(namespace)
      # Fallback contract is a plain Class.new with validate/save/errors
      contract_class = namespace.const_get(loader.contract_class_name)
      model = Struct.new(:save).new(true)
      contract = contract_class.new(model)
      expect(contract.validate({})).to be true
      expect(contract.errors).to eq([])
    end
  end

  describe "blueprint model: destroy and persisted?" do
    before { described_class.new(nil).load_into(namespace) }

    it "destroy on blueprint model returns true" do
      model = namespace::BlueprintEntity.new
      expect(model.destroy).to be true
    end

    it "persisted? on blueprint model returns false" do
      model = namespace::BlueprintEntity.new
      expect(model.persisted?).to be false
    end
  end

  describe "blueprint contract: validate without attributes=" do
    before { described_class.new(nil).load_into(namespace) }

    it "validate returns true when model does not respond to attributes=" do
      plain_model = Object.new  # does not have attributes= method
      contract = namespace::BlueprintEntityContract.new(plain_model)
      expect(contract.validate(name: "test")).to be true
    end
  end

  describe "blueprint contract: save when model has/lacks save" do
    before { described_class.new(nil).load_into(namespace) }

    it "calls model.save when model responds to save" do
      model_with_save = double("model", "attributes=": nil, save: :saved_result)
      contract = namespace::BlueprintEntityContract.new(model_with_save)
      contract.validate({})
      expect(contract.save).to eq(:saved_result)
    end

    it "returns nil when model does not respond to save" do
      no_save = Object.new
      contract = namespace::BlueprintEntityContract.new(no_save)
      expect(contract.save).to be_nil
    end
  end

  describe "define_fallback_model const_defined? guard" do
    it "does not raise when called twice (second call is no-op)" do
      loader = described_class.new(nil)
      loader.send(:define_fallback_model, namespace)
      # Second call should hit the const_defined? guard and return early
      expect { loader.send(:define_fallback_model, namespace) }.not_to raise_error
    end
  end

  describe "define_fallback_contract const_defined? guard" do
    it "does not raise when called twice (second call is no-op)" do
      loader = described_class.new(nil)
      loader.send(:define_fallback_contract, namespace)
      expect { loader.send(:define_fallback_contract, namespace) }.not_to raise_error
    end
  end

  describe "fallback model interface" do
    it "supports attributes accessor and save" do
      loader = described_class.new(nil)
      loader.send(:define_fallback_model, namespace)
      klass = namespace.const_get(loader.model_class_name)
      instance = klass.new(foo: "bar")
      expect(instance.attributes).to eq(foo: "bar")
      expect(instance.save).to be true
    end
  end

  describe "fallback contract interface" do
    it "supports validate (returns true) and save (delegates to model)" do
      loader = described_class.new(nil)
      loader.send(:define_fallback_contract, namespace)
      contract_klass = namespace.const_get(loader.contract_class_name)
      model = double("model", save: true)
      allow(model).to receive(:respond_to?).with(:save).and_return(true)
      contract = contract_klass.new(model)
      expect(contract.validate({})).to be true
      expect(contract.save).to be true
      expect(contract.errors).to eq([])
    end
  end

  describe "integration with ActivityClassBuilder" do    let(:entity) do
      create(:entity,
        name: "Task",
        property_schema: [
          { "name" => "title", "name_slug" => "title", "type" => "Types::String" }
        ].to_json
      )
    end
    let(:loader) { described_class.new(entity) }

    it "loaded classes can be used by activity code" do
      loader.load_into(namespace)

      activity_code = <<~RUBY
        class TestActivity < Trailblazer::Activity::Railway
          step :create_task

          def create_task(ctx, **)
            ctx[:task] = Task.new
            true
          end
        end
      RUBY

      namespace.module_eval(activity_code)

      expect(namespace.const_defined?(:TestActivity)).to be true
      expect(namespace::TestActivity.ancestors).to include(Trailblazer::Activity::Railway)
    end
  end
end
