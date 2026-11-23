# frozen_string_literal: true

require "rails_helper"

RSpec.describe "FlowchartRuntime::Outputs" do
  subject(:facade) { "FlowchartRuntime::Outputs".constantize }

  describe ".latest" do
    it "returns the value of the first key present in a Hash" do
      ctx = { status_ab12: "approved", status: "pending" }
      expect(facade.latest(ctx, :status_ab12, :status)).to eq("approved")
    end

    it "skips missing keys and returns a later present value" do
      ctx = { status: "pending" }
      expect(facade.latest(ctx, :status_ab12, :status)).to eq("pending")
    end

    it "returns nil when no key is present" do
      expect(facade.latest({}, :status, :reviewer)).to be_nil
    end

    it "preserves an explicit nil stored under a present key" do
      ctx = { reviewer: nil, fallback: "team" }
      expect(facade.latest(ctx, :reviewer, :fallback)).to be_nil
    end

    it "reads the first present key from a Trailblazer::Context" do
      ctx = Trailblazer::Context({ status_ab12: "approved", status: "pending" })
      expect(facade.latest(ctx, :status_ab12, :status)).to eq("approved")
      expect(facade.latest(ctx, :missing, :status)).to eq("pending")
      expect(facade.latest(ctx, :missing)).to be_nil
    end
  end

  describe ".view" do
    it "returns { pin => value } for the first present key" do
      ctx = { status_ab12: "approved", status: "pending" }
      expect(facade.view(ctx, :status, :status_ab12, :status)).to eq(status: "approved")
    end

    it "preserves an explicit nil or false stored under a present key" do
      expect(facade.view({ reviewer: nil }, :reviewer, :reviewer)).to eq(reviewer: nil)
      expect(facade.view({ flag: false }, :flag, :flag)).to eq(flag: false)
    end

    it "returns an empty hash when no key is present" do
      expect(facade.view({}, :status, :status_ab12, :status)).to eq({})
    end

    it "keeps Hash dig/fetch/key? semantics on a Trailblazer::Context" do
      ctx = Trailblazer::Context({ status_ab12: "approved" })
      view = facade.view(ctx, :status, :status_ab12, :status)
      expect(view.dig(:status)).to eq("approved")
      expect(view.fetch(:status, "missing")).to eq("approved")
      expect(view.key?(:status)).to be(true)
      expect(facade.view(ctx, :status, :missing).fetch(:status, "fallback")).to eq("fallback")
      expect(facade.view(ctx, :status, :missing).key?(:status)).to be(false)
    end
  end
end
