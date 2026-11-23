# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Invocable do
  describe ".job!" do
    it "resolves ApplicationJob" do
      expect(described_class.job!("ApplicationJob")).to eq(ApplicationJob)
    end

    it "rejects non-job constants" do
      expect { described_class.job!("String") }.to raise_error(FlowchartRuntime::Invocable::Error, /not allowlisted|unknown/)
    end

    it "rejects invalid names" do
      expect { described_class.job!("Kernel; exit") }.to raise_error(FlowchartRuntime::Invocable::Error, /invalid/)
    end
  end

  describe ".service!" do
    it "allows Emails::Gateway" do
      expect(described_class.service!("Emails::Gateway")).to eq(Emails::Gateway)
    end

    it "rejects Kernel" do
      expect { described_class.service!("Kernel") }.to raise_error(FlowchartRuntime::Invocable::Error)
    end

    it "rejects an ActiveRecord class even when the namespace is allowlisted" do
      expect { described_class.service!("Emails::Credential") }
        .to raise_error(FlowchartRuntime::Invocable::Error, /ActiveRecord/)
    end
  end

  describe ".mailer!" do
    it "resolves ApplicationMailer from allowlist" do
      expect(described_class.mailer!("ApplicationMailer")).to eq(ApplicationMailer)
    end

    it "rejects non-allowlisted mailers" do
      expect { described_class.mailer!("Object") }.to raise_error(FlowchartRuntime::Invocable::Error)
    end
  end

  describe ".method_name!" do
    it "accepts simple identifiers" do
      expect(described_class.method_name!("notify")).to eq("notify")
    end

    it "rejects injection" do
      expect { described_class.method_name!("x; exit") }.to raise_error(FlowchartRuntime::Invocable::Error)
    end

    %w[delete_all destroy_all update_all delete destroy update_column update_columns insert_all upsert_all find_by_sql connection].each do |name|
      it "rejects #{name}" do
        expect { described_class.method_name!(name) }.to raise_error(FlowchartRuntime::Invocable::Error)
      end
    end
  end

  describe ".call!" do
    it "invokes an allow-listed Service.call" do
      input = { "qty" => "2" }
      field = Struct.new(:name, :type, keyword_init: true).new(name: "qty", type: "integer")
      expect(described_class.call!(FeatureModules::InputCaster, input: input, fields: [field]))
        .to eq("qty" => 2)
    end

    it "wraps ArgumentError as Invocable::Error" do
      expect { described_class.call!(FeatureModules::InputCaster) }
        .to raise_error(described_class::Error)
    end
  end

  describe ".failed?" do
    it "treats a Result with ok false as a failure" do
      result = Struct.new(:ok).new(false)
      expect(described_class.failed?(result)).to be(true)
    end

    it "does not treat false or nil as a Result failure" do
      expect(described_class.failed?(false)).to be(false)
      expect(described_class.failed?(nil)).to be(false)
    end
  end

  describe ".fail_result" do
    it "copies Result errors onto ctx" do
      result = Struct.new(:ok, :errors, keyword_init: true).new(ok: false, errors: ["nope"])
      ctx = { errors: [] }
      expect(described_class.fail_result(ctx, result)).to be(false)
      expect(ctx[:errors]).to include("nope")
    end
  end

  describe ".method!" do
    it "allows Emails::Gateway.send because it is defined under app/" do
      expect(described_class.method!(Emails::Gateway, "send", style: "class_method")).to eq("send")
    end

    it "allows Captcha::VerificationContext.new when initialize is defined under app/" do
      expect(described_class.method!(Captcha::VerificationContext, "new", style: "class_method")).to eq("new")
    end

    %w[instance_eval public_send __send__ eval system].each do |name|
      it "rejects #{name} on an allowlisted namespace" do
        expect { described_class.method!(Emails::Gateway, name, style: "class_method") }
          .to raise_error(FlowchartRuntime::Invocable::Error)
      end
    end

    it "still rejects AR delete_all by name" do
      expect { described_class.method!(Emails::Gateway, "delete_all", style: "class_method") }
        .to raise_error(FlowchartRuntime::Invocable::Error)
    end
  end
end
