# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::EmissionRewriter, ".call_element" do
  def rewrite(body:, element_id:, io_overrides: {}, rename_map: {}, reachability: {},
              producer_outputs: {}, dominators: {}, topo_index: {})
    described_class.call_element(
      body:             body,
      element_id:       element_id,
      io_overrides:     io_overrides,
      rename_map:       rename_map,
      reachability:     reachability,
      producer_outputs: producer_outputs,
      dominators:       dominators,
      topo_index:       topo_index
    )
  end

  it "rewrites writes using element output overrides" do
    result = rewrite(
      body:         "ctx[:model] = {id: 1}\nctx[:other] = true",
      element_id:   "e1",
      io_overrides: { "outputs" => [{ "pin" => "model", "renamed_to" => "model_a3f2" }] }
    )
    expect(result).to include("ctx[:model_a3f2] = {id: 1}")
    expect(result).to include("ctx[:other] = true")
  end

  it "rewrites reads using explicit input override" do
    result = rewrite(
      body:         "x = ctx[:model]",
      element_id:   "e2",
      io_overrides: { "inputs" => [{ "pin" => "model", "override_key" => "model_e7c1" }] }
    )
    expect(result).to eq("x = ctx[:model_e7c1]")
  end

  it "uses a single candidate's effective key directly" do
    result = rewrite(
      body:             "x = ctx[:model]",
      element_id:       "reader",
      rename_map:       { "producer" => { "model" => "model_ab12" } },
      reachability:     { "reader" => %w[root producer] },
      producer_outputs: { "producer" => %w[model], "root" => %w[token] },
      topo_index:       { "root" => 0, "producer" => 1, "reader" => 2 }
    )
    expect(result).to eq("x = ctx[:model_ab12]")
  end

  describe "implied Entries.scope(ctx) reads" do
    let(:body) { "ctx[:values] = FlowchartRuntime::Entries.scope(ctx).pluck(:name)\ntrue" }

    it "keeps the whole ctx argument when one upstream element writes bound_entity" do
      result = rewrite(
        body:             body,
        element_id:       "reader",
        reachability:     { "reader" => %w[assign] },
        producer_outputs: { "assign" => %w[bound_entity] },
        topo_index:       { "assign" => 0, "reader" => 1 }
      )
      expect(result).to eq(body)
    end

    it "keeps the whole ctx argument when several upstream elements write customer_id" do
      result = rewrite(
        body:             body,
        element_id:       "reader",
        rename_map:       { "b" => { "customer_id" => "customer_id_b1" } },
        reachability:     { "reader" => %w[a b] },
        producer_outputs: { "a" => %w[customer_id], "b" => %w[customer_id] },
        topo_index:       { "a" => 0, "b" => 1, "reader" => 2 }
      )
      expect(result).to eq(body)
    end

    it "keeps the whole ctx argument under an explicit input override" do
      result = rewrite(
        body:         body,
        element_id:   "reader",
        io_overrides: { "inputs" => [{ "pin" => "bound_entity", "override_key" => "other_entity" }] }
      )
      expect(result).to eq(body)
    end
  end

  it "leaves reads unchanged when no override and no candidate producer" do
    result = rewrite(
      body:         "x = ctx[:model]",
      element_id:   "reader",
      reachability: { "reader" => [] }
    )
    expect(result).to eq("x = ctx[:model]")
  end

  it "honors an empty-string override_key tombstone (no producer fallback)" do
    result = rewrite(
      body:             "x = ctx[:model]",
      element_id:       "reader",
      io_overrides:     { "inputs" => [{ "pin" => "model", "override_key" => "" }] },
      rename_map:       { "producer" => { "model" => "model_ab12" } },
      reachability:     { "reader" => %w[producer] },
      producer_outputs: { "producer" => %w[model] }
    )
    expect(result).to eq("x = ctx[:model]")
  end

  it "preserves reverse-order splice correctness with multiple edits" do
    result = rewrite(
      body:         "ctx[:model] = ctx[:model]; ctx[:flag] = true",
      element_id:   "e3",
      io_overrides: {
        "inputs"  => [{ "pin" => "model", "override_key" => "model_src" }],
        "outputs" => [{ "pin" => "model", "renamed_to"   => "model_dst" }]
      }
    )
    expect(result).to eq("ctx[:model_dst] = ctx[:model_src]; ctx[:flag] = true")
  end

  it "accepts symbol-keyed io_overrides (symbol hash and symbol entries)" do
    result = rewrite(
      body:         "x = ctx[:model]\nctx[:model] = 1",
      element_id:   "e_sym",
      io_overrides: {
        inputs:  [{ pin: "model", override_key: "model_sym_in" }],
        outputs: [{ pin: "model", renamed_to:   "model_sym_out" }]
      }
    )
    expect(result).to eq("x = ctx[:model_sym_in]\nctx[:model_sym_out] = 1")
  end

  it "prefers explicit input override over candidate producers" do
    result = rewrite(
      body:             "x = ctx[:model]",
      element_id:       "reader",
      io_overrides:     { "inputs" => [{ "pin" => "model", "override_key" => "model_explicit" }] },
      rename_map:       { "producer" => { "model" => "model_producer_rename" } },
      reachability:     { "reader" => %w[producer] },
      producer_outputs: { "producer" => %w[model] }
    )
    expect(result).to eq("x = ctx[:model_explicit]")
  end

  it "reads a dominating latest candidate's key directly" do
    result = rewrite(
      body:             "x = ctx[:model]",
      element_id:       "reader",
      rename_map:       {
        "far"  => { "model" => "model_far" },
        "near" => { "model" => "model_near" }
      },
      reachability:     { "reader" => %w[far near] },
      producer_outputs: { "far" => %w[model], "near" => %w[model] },
      dominators:       { "reader" => %w[start far near reader].to_set },
      topo_index:       { "start" => 0, "far" => 1, "near" => 2, "reader" => 3 }
    )
    expect(result).to eq("x = ctx[:model_near]")
  end

  it "emits Outputs.latest with keys latest-first when the latest candidate does not dominate" do
    result = rewrite(
      body:             "x = ctx[:model]",
      element_id:       "reader",
      rename_map:       {
        "left"  => { "model" => "model_left" },
        "right" => { "model" => "model_right" }
      },
      reachability:     { "reader" => %w[start left right] },
      producer_outputs: { "left" => %w[model], "right" => %w[model] },
      dominators:       { "reader" => %w[start reader].to_set },
      topo_index:       { "start" => 0, "left" => 1, "right" => 2, "reader" => 3 }
    )
    expect(result).to eq("x = FlowchartRuntime::Outputs.latest(ctx, :model_right, :model_left)")
  end

  it "lets a self-writer read upstream candidates before its own write" do
    result = rewrite(
      body:             "ctx[:count] = ctx[:count].to_i + 1",
      element_id:       "bump",
      io_overrides:     { "outputs" => [{ "pin" => "count", "renamed_to" => "count_ab12" }] },
      rename_map:       { "bump" => { "count" => "count_ab12" } },
      reachability:     { "bump" => %w[seed] },
      producer_outputs: { "seed" => %w[count], "bump" => %w[count] },
      dominators:       { "bump" => %w[seed bump].to_set },
      topo_index:       { "seed" => 0, "bump" => 1 }
    )
    expect(result).to eq("ctx[:count_ab12] = FlowchartRuntime::Outputs.latest(ctx, :count_ab12, :count).to_i + 1")
  end

  it "keeps an op-assign as a write to the element's own key" do
    result = rewrite(
      body:             "ctx[:count] += 1",
      element_id:       "bump",
      io_overrides:     { "outputs" => [{ "pin" => "count", "renamed_to" => "count_ab12" }] },
      rename_map:       { "bump" => { "count" => "count_ab12" } },
      reachability:     { "bump" => %w[seed] },
      producer_outputs: { "seed" => %w[count], "bump" => %w[count] },
      dominators:       { "bump" => %w[seed bump].to_set },
      topo_index:       { "seed" => 0, "bump" => 1 }
    )
    expect(result).to eq("ctx[:count_ab12] += 1")
  end

  it "replaces only the :pin symbol in ctx.dig when a single candidate was renamed" do
    result = rewrite(
      body:             "x = ctx.dig(:model, :id)",
      element_id:       "reader",
      rename_map:       { "producer" => { "model" => "model_ab12" } },
      reachability:     { "reader" => %w[producer] },
      producer_outputs: { "producer" => %w[model] },
      topo_index:       { "producer" => 0, "reader" => 1 }
    )
    expect(result).to eq("x = ctx.dig(:model_ab12, :id)")
  end

  it "replaces only the :pin symbol in ctx.fetch and ctx.key? for a renamed producer" do
    result = rewrite(
      body:             "ctx.fetch(:model, 0); ctx.key?(:model)",
      element_id:       "reader",
      rename_map:       { "producer" => { "model" => "model_ab12" } },
      reachability:     { "reader" => %w[producer] },
      producer_outputs: { "producer" => %w[model] },
      topo_index:       { "producer" => 0, "reader" => 1 }
    )
    expect(result).to eq("ctx.fetch(:model_ab12, 0); ctx.key?(:model_ab12)")
  end

  it "replaces only the ctx receiver with Outputs.view for a non-dominating dig/fetch/key?" do
    result = rewrite(
      body:             "ctx.dig(:model); ctx.fetch(:model, 0); ctx.key?(:model)",
      element_id:       "reader",
      rename_map:       {
        "left"  => { "model" => "model_left" },
        "right" => { "model" => "model_right" }
      },
      reachability:     { "reader" => %w[start left right] },
      producer_outputs: { "left" => %w[model], "right" => %w[model] },
      dominators:       { "reader" => %w[start reader].to_set },
      topo_index:       { "start" => 0, "left" => 1, "right" => 2, "reader" => 3 }
    )
    view = "FlowchartRuntime::Outputs.view(ctx, :model, :model_right, :model_left)"
    expect(result).to eq("#{view}.dig(:model); #{view}.fetch(:model, 0); #{view}.key?(:model)")
  end

  it "leaves a tombstoned dig as ctx.dig(:pin)" do
    result = rewrite(
      body:             "x = ctx.dig(:model)",
      element_id:       "reader",
      io_overrides:     { "inputs" => [{ "pin" => "model", "override_key" => "" }] },
      rename_map:       { "producer" => { "model" => "model_ab12" } },
      reachability:     { "reader" => %w[producer] },
      producer_outputs: { "producer" => %w[model] }
    )
    expect(result).to eq("x = ctx.dig(:model)")
  end

  it "honors an explicit input override on a dig by rewriting only the symbol" do
    result = rewrite(
      body:         "x = ctx.dig(:model)",
      element_id:   "reader",
      io_overrides: { "inputs" => [{ "pin" => "model", "override_key" => "model_explicit" }] }
    )
    expect(result).to eq("x = ctx.dig(:model_explicit)")
  end

  describe "byte-exact splices after CJK text" do
    let(:cjk) { '"你好世界"; ' }

    it "rewrites a ctx[:pin] read after CJK when a single producer was renamed" do
      result = rewrite(
        body:             "#{cjk}x = ctx[:v]",
        element_id:       "reader",
        rename_map:       { "producer" => { "v" => "v_ab12" } },
        reachability:     { "reader" => %w[producer] },
        producer_outputs: { "producer" => %w[v] },
        topo_index:       { "producer" => 0, "reader" => 1 }
      )
      expect(result).to eq("#{cjk}x = ctx[:v_ab12]")
    end

    it "rewrites a ctx[:pin] selection after CJK" do
      result = rewrite(
        body:             "#{cjk}x = ctx[:v]",
        element_id:       "reader",
        rename_map:       {
          "left"  => { "v" => "v_left" },
          "right" => { "v" => "v_right" }
        },
        reachability:     { "reader" => %w[start left right] },
        producer_outputs: { "left" => %w[v], "right" => %w[v] },
        dominators:       { "reader" => %w[start reader].to_set },
        topo_index:       { "start" => 0, "left" => 1, "right" => 2, "reader" => 3 }
      )
      expect(result).to eq("#{cjk}x = FlowchartRuntime::Outputs.latest(ctx, :v_right, :v_left)")
    end

    it "rewrites a ctx.dig read after CJK when a single producer was renamed" do
      result = rewrite(
        body:             "#{cjk}x = ctx.dig(:v)",
        element_id:       "reader",
        rename_map:       { "producer" => { "v" => "v_ab12" } },
        reachability:     { "reader" => %w[producer] },
        producer_outputs: { "producer" => %w[v] },
        topo_index:       { "producer" => 0, "reader" => 1 }
      )
      expect(result).to eq("#{cjk}x = ctx.dig(:v_ab12)")
    end

    it "rewrites a ctx.dig selection after CJK by replacing only the receiver" do
      result = rewrite(
        body:             "#{cjk}x = ctx.dig(:v)",
        element_id:       "reader",
        rename_map:       {
          "left"  => { "v" => "v_left" },
          "right" => { "v" => "v_right" }
        },
        reachability:     { "reader" => %w[start left right] },
        producer_outputs: { "left" => %w[v], "right" => %w[v] },
        dominators:       { "reader" => %w[start reader].to_set },
        topo_index:       { "start" => 0, "left" => 1, "right" => 2, "reader" => 3 }
      )
      expect(result).to eq("#{cjk}x = FlowchartRuntime::Outputs.view(ctx, :v, :v_right, :v_left).dig(:v)")
    end
  end
end
