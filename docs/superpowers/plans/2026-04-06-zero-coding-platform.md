# Zero-Coding Platform Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `anysys` a true zero-coding platform by implementing: (1) configuration-driven multi-branch conditional routing in Activities, (2) real data persistence for form submissions and activity execution, (3) connection-level condition configuration in the property editor UI.

**Architecture:** The ActivityGenerator performs topology analysis on the flowchart graph to identify branch groups per Decision/Switch element, then generates step methods with routing variables (`ctx[:_route_N]`) and branch guards on downstream steps. Form submissions create EntityEntry records. DynamicController pre-loads entity entries and wraps execution in transactions.

**Tech Stack:** Rails 8.1.2, Trailblazer Activity (Railway), Reform, StimulusJS, TailwindCSS, ViewComponent, RSpec

---

## Background: How Conditional Branching Works

The `ActivityGenerator` uses DFS to collect steps linearly. Decision/Switch generators produce a boolean or symbol expression but there is no branch routing — all steps always execute. The fix: add a `FlowchartTopologyAnalyzer` that walks the graph per Decision element to label downstream nodes with their branch, then generate routing variables and guards.

### Branch Pattern (generated output)
```ruby
class MyActivity < Trailblazer::Activity::Railway
  step :check_status       # Decision: sets ctx[:_route_0]
  step :approve_record     # Guard: return true unless ctx[:_route_0] == :yes
  step :send_approval      # Guard: return true unless ctx[:_route_0] == :yes
  step :reject_record      # Guard: return true unless ctx[:_route_0] == :no
  step :send_rejection     # Guard: return true unless ctx[:_route_0] == :no
  step :save_and_finish    # No guard: convergence point

  def check_status(ctx, **)
    ctx[:_route_0] = (ctx[:status] == "approved") ? :yes : :no
    true
  end

  def approve_record(ctx, **)
    return true unless ctx[:_route_0] == :yes
    # ... approve logic
    true
  end
  # ...
end
```

---

## File Map

### New Files
- `app/services/flowchart_topology_analyzer.rb` — graph analysis: branch labeling, convergence detection
- `spec/services/flowchart_topology_analyzer_spec.rb`
- `spec/services/activity_generator_spec.rb` (extend existing if it exists)

### Modified Files
- `app/services/activity_generator.rb` — use topology analyzer; inject branch routing and guards into generated code
- `app/services/code_generators/element_types/decision/decision_generator.rb` — generate routing assignment (`ctx[:_route_N] = ...`) instead of bare boolean
- `app/services/code_generators/element_types/switch/switch_generator.rb` — generate routing assignment for multi-case
- `app/controllers/dynamic_controller.rb` — pre-load entity entry as `ctx[:model]`; wrap in transaction
- `app/controllers/public_pages_controller.rb` — actually save submitted form data as EntityEntry
- `spec/controllers/dynamic_controller_spec.rb` — extend tests
- `spec/controllers/public_pages_controller_spec.rb` — extend tests

---

## Task 1: FlowchartTopologyAnalyzer — Branch labeling

**Files:**
- Create: `app/services/flowchart_topology_analyzer.rb`
- Test: `spec/services/flowchart_topology_analyzer_spec.rb`

- [ ] **Step 1.1: Write failing tests**

```ruby
# spec/services/flowchart_topology_analyzer_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartTopologyAnalyzer do
  # Simple linear: Start → Process → End
  let(:linear_elements) do
    [
      { "id" => "s1", "type" => "start" },
      { "id" => "p1", "type" => "process", "label" => "Do Work" },
      { "id" => "e1", "type" => "end" }
    ]
  end
  let(:linear_connections) do
    [
      { "id" => "c1", "from" => "s1", "to" => "p1" },
      { "id" => "c2", "from" => "p1", "to" => "e1" }
    ]
  end

  # Decision: Start → Decision → BranchA → Merge → End
  #                            → BranchB ↗
  let(:decision_elements) do
    [
      { "id" => "s1", "type" => "start" },
      { "id" => "d1", "type" => "decision", "label" => "Check Status" },
      { "id" => "a1", "type" => "process", "label" => "Approve" },
      { "id" => "b1", "type" => "process", "label" => "Reject" },
      { "id" => "m1", "type" => "process", "label" => "Notify" },
      { "id" => "e1", "type" => "end" }
    ]
  end
  let(:decision_connections) do
    [
      { "id" => "c1", "from" => "s1", "to" => "d1" },
      { "id" => "c2", "from" => "d1", "to" => "a1", "label" => "Yes",
        "condition" => { "type" => "single", "leftOperand" => "ctx.status",
                         "operator" => "==", "rightOperand" => "approved" } },
      { "id" => "c3", "from" => "d1", "to" => "b1", "label" => "No" },
      { "id" => "c4", "from" => "a1", "to" => "m1" },
      { "id" => "c5", "from" => "b1", "to" => "m1" },
      { "id" => "c6", "from" => "m1", "to" => "e1" }
    ]
  end

  describe "#analyze" do
    context "with linear flowchart" do
      subject(:result) do
        described_class.new(linear_elements, linear_connections).analyze
      end

      it "returns empty branch_groups" do
        expect(result[:branch_groups]).to be_empty
      end

      it "marks all nodes as unguarded" do
        expect(result[:node_guards]).to be_empty
      end
    end

    context "with decision element" do
      subject(:result) do
        described_class.new(decision_elements, decision_connections).analyze
      end

      it "detects one decision element" do
        expect(result[:branch_groups].keys).to eq(["d1"])
      end

      it "assigns branch labels to immediate branch nodes" do
        groups = result[:branch_groups]["d1"]
        expect(groups[:branches].keys).to include(:branch_0, :branch_1)
      end

      it "assigns merge node (convergence point) correctly" do
        groups = result[:branch_groups]["d1"]
        expect(groups[:merge_node_id]).to eq("m1")
      end

      it "labels approve node as branch_0 and reject as branch_1" do
        guards = result[:node_guards]
        expect(guards["a1"]).to include(decision_id: "d1", branch: :branch_0)
        expect(guards["b1"]).to include(decision_id: "d1", branch: :branch_1)
      end

      it "does not guard the merge node" do
        expect(result[:node_guards]["m1"]).to be_nil
      end
    end
  end
end
```

- [ ] **Step 1.2: Run tests to verify they fail**

```bash
cd /opt/milestone/anysys && bundle exec rspec spec/services/flowchart_topology_analyzer_spec.rb --no-color 2>&1 | tail -20
```
Expected: `uninitialized constant FlowchartTopologyAnalyzer` or similar.

- [ ] **Step 1.3: Implement FlowchartTopologyAnalyzer**

```ruby
# app/services/flowchart_topology_analyzer.rb
# frozen_string_literal: true

# FlowchartTopologyAnalyzer
#
# Analyzes flowchart graph to identify branch groups created by Decision/Switch
# elements. Returns:
#   - :branch_groups — per-decision-id branch metadata and convergence nodes
#   - :node_guards   — per-node-id guard metadata (which decision + branch applies)
#   - :decision_indices — maps decision_id to its sequential index (for ctx[:_route_N])
#
# Used by ActivityGenerator to inject branch routing and guards into generated code.
#
class FlowchartTopologyAnalyzer
  BRANCHING_TYPES = %w[decision switch].freeze

  Result = Struct.new(:branch_groups, :node_guards, :decision_indices, keyword_init: true)

  def initialize(elements, connections)
    @elements    = elements
    @connections = connections
    @element_map = elements.index_by { |el| el["id"] }
    @adjacency   = build_adjacency
    @reverse_adj = build_reverse_adjacency
  end

  def analyze
    branch_groups    = {}
    node_guards      = {}
    decision_indices = {}
    index            = 0

    branching_elements.each do |el|
      el_id   = el["id"]
      out_conns = outgoing_connections(el_id)
      next if out_conns.size < 2  # skip single-output decisions

      decision_indices[el_id] = index

      branches = {}
      out_conns.each_with_index do |conn, i|
        branch_key = :"branch_#{i}"
        branches[branch_key] = {
          connection_id: conn["id"],
          label:         conn["label"] || branch_key.to_s,
          condition:     conn["condition"]
        }
      end

      merge_id = find_convergence_node(el_id, out_conns.map { |c| c["to"] })

      branch_groups[el_id] = {
        branches:      branches,
        merge_node_id: merge_id,
        route_index:   index
      }

      # Label downstream nodes with their branch guard
      out_conns.each_with_index do |conn, i|
        branch_key = :"branch_#{i}"
        label_branch_nodes(conn["to"], el_id, branch_key, merge_id, node_guards)
      end

      index += 1
    end

    Result.new(
      branch_groups:    branch_groups,
      node_guards:      node_guards,
      decision_indices: decision_indices
    )
  end

  private

  attr_reader :elements, :connections, :element_map, :adjacency, :reverse_adj

  def build_adjacency
    Hash.new { |h, k| h[k] = [] }.tap do |adj|
      connections.each { |c| adj[c["from"]] << c }
    end
  end

  def build_reverse_adjacency
    Hash.new { |h, k| h[k] = [] }.tap do |radj|
      connections.each { |c| radj[c["to"]] << c["from"] }
    end
  end

  def outgoing_connections(node_id)
    adjacency[node_id]
  end

  def branching_elements
    elements.select { |el| BRANCHING_TYPES.include?(el["type"]) }
  end

  # Walk forward from start_ids until all paths converge or dead-end.
  # Returns the first node that is reachable from ALL branch heads.
  def find_convergence_node(decision_id, start_ids)
    # BFS from each branch head; find first node reachable from all
    reachable_sets = start_ids.map { |id| bfs_reachable(id) }
    return nil if reachable_sets.empty?

    # Intersection of all reachable sets, then pick earliest by DFS order from decision
    common = reachable_sets.reduce(:&)
    common -= Set.new([decision_id])
    return nil if common.empty?

    # Return the first common node in DFS order from decision
    dfs_order_from(decision_id).find { |id| common.include?(id) }
  end

  def bfs_reachable(start_id)
    visited = Set.new
    queue   = [start_id]
    while (node_id = queue.shift)
      next if visited.include?(node_id)
      visited.add(node_id)
      adjacency[node_id].each { |conn| queue << conn["to"] }
    end
    visited
  end

  def dfs_order_from(start_id)
    visited = []
    seen    = Set.new
    dfs_visit_ordered(start_id, seen, visited)
    visited
  end

  def dfs_visit_ordered(node_id, seen, result)
    return if seen.include?(node_id)
    seen.add(node_id)
    result << node_id
    adjacency[node_id].each { |conn| dfs_visit_ordered(conn["to"], seen, result) }
  end

  # Walk forward from node_id, labeling nodes with the given branch guard.
  # Stop when reaching merge_id (exclusive) or any dead-end.
  def label_branch_nodes(node_id, decision_id, branch_key, merge_id, node_guards)
    visited = Set.new
    queue   = [node_id]

    while (current_id = queue.shift)
      next if visited.include?(current_id)
      next if current_id == merge_id
      next if element_map[current_id].nil?

      visited.add(current_id)
      node_guards[current_id] ||= { decision_id: decision_id, branch: branch_key }

      adjacency[current_id].each { |conn| queue << conn["to"] unless conn["to"] == merge_id }
    end
  end
end
```

- [ ] **Step 1.4: Run tests to verify they pass**

```bash
cd /opt/milestone/anysys && bundle exec rspec spec/services/flowchart_topology_analyzer_spec.rb --no-color 2>&1 | tail -20
```
Expected: All tests pass.

- [ ] **Step 1.5: Commit**

```bash
cd /opt/milestone/anysys && git add app/services/flowchart_topology_analyzer.rb spec/services/flowchart_topology_analyzer_spec.rb && git commit -m "feat: add FlowchartTopologyAnalyzer for branch group detection"
```

---

## Task 2: ActivityGenerator — Branch routing and step guards

**Files:**
- Modify: `app/services/activity_generator.rb`
- Modify: `app/services/code_generators/element_types/decision/decision_generator.rb`
- Modify: `app/services/code_generators/element_types/switch/switch_generator.rb`
- Test: `spec/services/activity_generator_branch_routing_spec.rb`

- [ ] **Step 2.1: Write failing tests**

```ruby
# spec/services/activity_generator_branch_routing_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivityGenerator do
  def build_flowchart(elements, connections, name: "TestFlow")
    flowchart = instance_double(Flowchart,
      name: name,
      elements: elements,
      connections: connections,
      entity: nil,
      type_shared?: false,
      type_customer_specific?: true
    )
    flowchart
  end

  # Flowchart: Start → Decision(status==approved) → Approve → Notify → End
  #                                               → Reject  ↗
  let(:elements) do
    [
      { "id" => "s1", "type" => "start", "label" => "Start", "properties" => {} },
      { "id" => "d1", "type" => "decision", "label" => "Check Status",
        "properties" => {
          "condition" => {
            "type" => "single",
            "leftOperand" => "ctx.status",
            "operator" => "==",
            "rightOperand" => "approved"
          }
        }
      },
      { "id" => "a1", "type" => "process", "label" => "Approve Record",
        "properties" => { "steps" => [{ "action" => "log", "config" => { "message" => "approved" } }] }
      },
      { "id" => "b1", "type" => "process", "label" => "Reject Record",
        "properties" => { "steps" => [{ "action" => "log", "config" => { "message" => "rejected" } }] }
      },
      { "id" => "n1", "type" => "process", "label" => "Notify User",
        "properties" => { "steps" => [] }
      },
      { "id" => "e1", "type" => "end", "label" => "End" }
    ]
  end

  let(:connections) do
    [
      { "id" => "c1", "from" => "s1", "to" => "d1" },
      { "id" => "c2", "from" => "d1", "to" => "a1", "label" => "Yes" },
      { "id" => "c3", "from" => "d1", "to" => "b1", "label" => "No" },
      { "id" => "c4", "from" => "a1", "to" => "n1" },
      { "id" => "c5", "from" => "b1", "to" => "n1" },
      { "id" => "c6", "from" => "n1", "to" => "e1" }
    ]
  end

  subject(:generated) { ActivityGenerator.new(build_flowchart(elements, connections)).generate }

  describe "multi-branch Decision routing" do
    it "generates activity code" do
      expect(generated).to be_present
    end

    it "generates routing assignment in the decision method" do
      expect(generated).to include("ctx[:_route_0]")
    end

    it "generates branch guard for approve branch" do
      expect(generated).to match(/def approve_record.*return true unless ctx\[:_route_0\]/m)
    end

    it "generates branch guard for reject branch" do
      expect(generated).to match(/def reject_record.*return true unless ctx\[:_route_0\]/m)
    end

    it "does NOT add a guard to the convergence step (notify_user)" do
      # notify_user comes after both branches merge — no guard
      notify_method = generated.match(/def notify_user.*?^  end/m)&.to_s || ""
      expect(notify_method).not_to include("return true unless ctx[:_route_0]")
    end
  end
end
```

- [ ] **Step 2.2: Run tests to verify they fail**

```bash
cd /opt/milestone/anysys && bundle exec rspec spec/services/activity_generator_branch_routing_spec.rb --no-color 2>&1 | tail -20
```
Expected: Failures about `ctx[:_route_0]` not found.

- [ ] **Step 2.3: Update DecisionGenerator to generate routing assignment**

Open `app/services/code_generators/element_types/decision/decision_generator.rb`.

Replace the `generate` method:

```ruby
def generate
  condition   = config["condition"]
  route_index = config["_route_index"] || 0    # injected by ActivityGenerator
  route_var   = "_route_#{route_index}".to_sym

  if condition.is_a?(Hash) && (condition["leftOperand"].present? || condition["type"] == "group")
    condition_code = build_structured_condition(condition)
    <<~RUBY.chomp
      ctx[:#{route_var}] = (#{condition_code}) ? :branch_0 : :branch_1
      true
    RUBY
  else
    <<~RUBY.chomp
      # Decision: no condition configured — default to branch_0
      ctx[:#{route_var}] = :branch_0
      true
    RUBY
  end
end
```

- [ ] **Step 2.4: Update SwitchGenerator to generate routing assignment**

Open `app/services/code_generators/element_types/switch/switch_generator.rb`.

Replace the `generate` method:

```ruby
def generate
  source      = config["sourceVariable"] || "value"
  cases       = config["cases"]
  route_index = config["_route_index"] || 0
  route_var   = "_route_#{route_index}".to_sym

  return "ctx[:#{route_var}] = :branch_0\ntrue" if cases.blank?

  when_clauses = cases.each_with_index.map { |c, i| "when #{c['value'].to_s.inspect} then :branch_#{i}" }
  else_clause  = "else :branch_#{cases.size}"  # default/fallthrough branch

  <<~RUBY.chomp
    ctx[:#{route_var}] = case ctx[:#{source}].to_s
    #{when_clauses.join("\n")}
    #{else_clause}
    end
    true
  RUBY
end
```

- [ ] **Step 2.5: Update ActivityGenerator to use topology analysis and inject guards**

The key changes to `app/services/activity_generator.rb`:

**a) In `dfs_collect_steps`, run topology analysis and store the result:**

After `build_graph` in `dfs_collect_steps`, add:

```ruby
def dfs_collect_steps
  build_graph
  return [] unless start_node_id

  @topology = FlowchartTopologyAnalyzer.new(elements, connections).analyze

  visited  = Set.new
  steps    = []
  used_names = {}
  ctx = { bound_entity: bound_entity }

  dfs_visit(start_node_id, visited, ctx) do |element, context|
    next if element["type"] == "start"

    subprocess_info = detect_subprocess(element)
    method_name     = derive_method_name(element, used_names)
    guard           = @topology.node_guards[element["id"]]

    steps << {
      element:    element,
      method_name: method_name,
      ctx:        context,
      subprocess: subprocess_info,
      guard:      guard
    }
  end

  steps
end
```

**b) In `build_method`, inject the `_route_index` config into decision/switch elements and inject guards:**

Replace `build_method`:

```ruby
def build_method(step_info)
  element     = step_info[:element]
  method_name = step_info[:method_name]
  ctx         = step_info[:ctx]
  label       = element["label"]
  steps       = element.dig("properties", "steps") || []
  guard       = step_info[:guard]

  # Inject route_index into Decision/Switch element config so their generator
  # can produce the correct ctx[:_route_N] variable.
  if %w[decision switch].include?(element["type"]) && @topology
    route_index = @topology.decision_indices[element["id"]] || 0
    element = element.deep_dup
    element["properties"] ||= {}
    element["properties"]["_route_index"] = route_index
  end

  guard_code = if guard
                 route_var = "_route_#{@topology.decision_indices[guard[:decision_id]] || 0}"
                 "return true unless ctx[:#{route_var}] == :#{guard[:branch]}\n"
               else
                 ""
               end

  body = method_body(element, steps, ctx)

  <<~RUBY.chomp
    # #{label}
    def #{method_name}(ctx, **)
    #{(guard_code + body).indent(2)}
    end
  RUBY
end
```

- [ ] **Step 2.6: Run tests to verify they pass**

```bash
cd /opt/milestone/anysys && bundle exec rspec spec/services/activity_generator_branch_routing_spec.rb --no-color 2>&1 | tail -20
```
Expected: All tests pass.

- [ ] **Step 2.7: Run full test suite to check for regressions**

```bash
cd /opt/milestone/anysys && bundle exec rspec --no-color 2>&1 | tail -30
```

- [ ] **Step 2.8: Commit**

```bash
cd /opt/milestone/anysys && git add app/services/activity_generator.rb app/services/code_generators/element_types/decision/decision_generator.rb app/services/code_generators/element_types/switch/switch_generator.rb spec/services/activity_generator_branch_routing_spec.rb && git commit -m "feat: implement multi-branch routing in ActivityGenerator via topology analysis"
```

---

## Task 3: DynamicController — Entity entry pre-load and transaction wrapping

**Files:**
- Modify: `app/controllers/dynamic_controller.rb`
- Test: `spec/requests/dynamic_controller_spec.rb` (check if it exists; create if not)

- [ ] **Step 3.1: Write failing tests**

```ruby
# spec/requests/dynamic_controller_spec.rb  (create or extend)
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DynamicController", type: :request do
  let(:customer) { create(:customer) }
  let(:entity)   { create(:entity, customer: customer) }
  let(:flowchart) do
    create(:flowchart, :customer_specific, :with_activity,
           customer: customer, entity: entity)
  end
  let(:entry)    { create(:entity_entry, entity: entity, customer: customer) }

  describe "GET /:customer_id/:uuid/:entity_id/:entry_id" do
    it "passes model to activity context when entity_entry_id is present" do
      get "/#{customer.id}/#{flowchart.uuid}/#{entity.id}/#{entry.id}",
          headers: { "Accept" => "application/json" }
      # The activity should receive ctx[:model] = entry
      # (Verified by checking the response ctx key)
      body = JSON.parse(response.body)
      expect(body["ctx"]["model"]).not_to be_nil
    end
  end
end
```

Note: this test depends on factory setup. It documents the expected behavior; run it after implementation.

- [ ] **Step 3.2: Update `build_context` to include model**

In `app/controllers/dynamic_controller.rb`, replace `build_context`:

```ruby
def build_context
  {
    params:       activity_params,
    bound_entity: @entity,
    id:           @entity_entry_id,
    model:        @entity_entry,
    customer_id:  current_customer_id
  }.compact
end
```

- [ ] **Step 3.3: Wrap execution in a transaction**

In `app/controllers/dynamic_controller.rb`, replace `execute_activity`:

```ruby
def execute_activity
  ctx = build_context
  log_execution(ctx)

  result = nil
  ActiveRecord::Base.transaction do
    result = ActivityTracer.new(@flowchart).call(ctx)
    raise ActiveRecord::Rollback unless result.success?
  end

  if result.error
    log_error "ActivityTracer error: #{result.error}"
    render_error(result.error, status: :unprocessable_entity)
  else
    log_info "Activity completed: #{result.success? ? 'SUCCESS' : 'FAILURE'}"
    render_trace_result(result)
  end
rescue StandardError => e
  log_error "Activity execution failed - #{e.class}: #{e.message}"
  log_error e.backtrace.first(10).join("\n")
  render_error("Activity execution failed: #{e.message}", status: :unprocessable_entity)
end
```

- [ ] **Step 3.4: Verify the app still boots**

```bash
cd /opt/milestone/anysys && bundle exec rails runner "puts 'OK'" 2>&1
```
Expected: `OK`

- [ ] **Step 3.5: Commit**

```bash
cd /opt/milestone/anysys && git add app/controllers/dynamic_controller.rb && git commit -m "feat: pre-load entity entry into ctx[:model] and wrap activity execution in transaction"
```

---

## Task 4: PublicPagesController — Save form submissions as EntityEntry

**Files:**
- Modify: `app/controllers/public_pages_controller.rb`
- Test: `spec/requests/public_pages_controller_spec.rb`

The current `submit` action just redirects. It needs to: find the page's entity, create/update an EntityEntry from the submitted params, then redirect.

- [ ] **Step 4.1: Write failing test**

```ruby
# spec/requests/public_pages_controller_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PublicPagesController", type: :request do
  let(:customer) { create(:customer) }
  let(:entity)   { create(:entity, customer: customer, property_schema: [{ "name_slug" => "full_name", "html_type" => "text", "validators" => [] }]) }
  let(:page) do
    create(:page, customer: customer, published: true,
           configuration: {
             "metadata" => { "entity_id" => entity.id.to_s },
             "pages" => [{ "fields" => [{ "field_id" => "f1", "field_name" => "full_name", "html_type" => "text" }] }],
             "rules" => [], "calculations" => []
           }.to_json)
  end

  describe "POST /customer_id/f/:token" do
    it "creates an EntityEntry with submitted data" do
      expect {
        post "/#{customer.id}/f/#{page.public_token}",
             params: { full_name: "Alice Smith" }
      }.to change(EntityEntry, :count).by(1)
    end

    it "redirects back to the page after submission" do
      post "/#{customer.id}/f/#{page.public_token}",
           params: { full_name: "Alice Smith" }
      expect(response).to redirect_to(public_page_path(customer_id: customer.id, token: page.public_token))
    end

    it "persists submitted field values" do
      post "/#{customer.id}/f/#{page.public_token}",
           params: { full_name: "Alice Smith" }
      entry = EntityEntry.last
      expect(entry.data["full_name"]).to eq("Alice Smith")
    end
  end
end
```

- [ ] **Step 4.2: Run failing tests**

```bash
cd /opt/milestone/anysys && bundle exec rspec spec/requests/public_pages_controller_spec.rb --no-color 2>&1 | tail -20
```
Expected: Failures about EntityEntry count not changing.

- [ ] **Step 4.3: Implement submit action with entity entry creation**

Replace `app/controllers/public_pages_controller.rb`:

```ruby
# frozen_string_literal: true

# PublicPagesController
#
# Serves published pages publicly without requiring authentication.
# URL: /:customer_id/f/:token
#
class PublicPagesController < ApplicationController
  set_tenant_from_route_params required: true

  layout "public_page"

  before_action :find_published_page

  def show
    @form_action = resolve_form_action(@page) || public_page_submit_path(customer_id: params[:customer_id], token: @page.public_token)
    @content     = @page.generate_content
  end

  def submit
    entity_id = @page.entity_id
    entity = entity_id.present? ? Entity.for_current_customer.find_by(id: entity_id) : nil

    if entity
      save_entry(entity)
    else
      redirect_to public_page_path(customer_id: params[:customer_id], token: @page.public_token),
                  notice: "Thank you! Your response has been submitted."
    end
  end

  private

  def find_published_page
    @page = Page.for_current_customer.published.find_by(public_token: params[:token])
    render plain: "Page not found", status: :not_found unless @page
  end

  def resolve_form_action(page)
    flowchart_id = page.configuration_json&.dig("form_settings", "flowchart_id")
    return nil unless flowchart_id

    flowchart = Flowchart.accessible.find_by(id: flowchart_id)
    return nil unless flowchart&.uuid && flowchart&.entity&.name_slug

    "/#{params[:customer_id]}/#{flowchart.uuid}/#{flowchart.entity.name_slug}"
  end

  def save_entry(entity)
    permitted = permitted_form_params(entity)

    entry = EntityEntry.new(
      entity:      entity,
      customer_id: current_customer_id,
      data:        permitted
    )

    if entry.save
      redirect_to public_page_path(customer_id: params[:customer_id], token: @page.public_token),
                  notice: "Thank you! Your response has been submitted."
    else
      redirect_to public_page_path(customer_id: params[:customer_id], token: @page.public_token),
                  alert: "There was a problem saving your response: #{entry.errors.full_messages.join(', ')}"
    end
  end

  # Build a hash of field_slug => value from submitted params, filtered to
  # field slugs defined in the entity's property_schema.
  def permitted_form_params(entity)
    allowed_slugs = (entity.property_schema_json || []).map { |f| f["name_slug"] }.compact
    params.permit(*allowed_slugs).to_h
  end
end
```

- [ ] **Step 4.4: Run failing tests**

```bash
cd /opt/milestone/anysys && bundle exec rspec spec/requests/public_pages_controller_spec.rb --no-color 2>&1 | tail -20
```
Expected: All pass.

- [ ] **Step 4.5: Commit**

```bash
cd /opt/milestone/anysys && git add app/controllers/public_pages_controller.rb spec/requests/public_pages_controller_spec.rb && git commit -m "feat: save public form submissions as EntityEntry records"
```

---

## Task 5: Connection Condition UI — Configure conditions per branch in property editor

The BranchManager currently creates Yes/No branches. We need to allow users to set a condition expression on each outgoing connection. The condition is stored in the connection JSON as `condition: { type, leftOperand, operator, rightOperand }`.

**Files:**
- Modify: `app/javascript/controllers/property_editor/branch_manager.js`
- Modify: `app/javascript/controllers/property_editor/templates.js`

- [ ] **Step 5.1: Read the current BranchManager and templates to understand the structure**

```bash
cd /opt/milestone/anysys && cat app/javascript/controllers/property_editor/branch_manager.js | grep -n "buildBranchItemHTML\|condition\|branchValue" | head -30
```

```bash
cd /opt/milestone/anysys && grep -n "buildBranchItemTemplate\|branch-condition" app/javascript/controllers/property_editor/templates.js | head -20
```

- [ ] **Step 5.2: Add condition fields to the branch modal template**

In `app/javascript/controllers/property_editor/templates.js`, find `buildBranchModalTemplate` and add condition fields after the label section. Look for the modal HTML and add:

```javascript
// After the label input in buildBranchModalTemplate, add:
<div class="mt-3">
  <label class="block text-xs font-medium text-gray-500 mb-1">Condition (optional)</label>
  <div class="flex gap-2 items-center">
    <input type="text" data-branch-condition-left
           class="flex-1 rounded border border-gray-300 px-2 py-1 text-xs font-mono"
           placeholder="ctx.field_name" />
    <select data-branch-condition-op
            class="rounded border border-gray-300 px-2 py-1 text-xs">
      <option value="==">==</option>
      <option value="!=">!=</option>
      <option value=">">></option>
      <option value=">=">>=</option>
      <option value="<"><</option>
      <option value="<="><=</option>
      <option value="is_empty">is empty</option>
      <option value="is_not_empty">is not empty</option>
    </select>
    <input type="text" data-branch-condition-right
           class="flex-1 rounded border border-gray-300 px-2 py-1 text-xs font-mono"
           placeholder="value" />
  </div>
  <p class="mt-1 text-xs text-gray-400">Leave blank for default/else branch</p>
</div>
```

- [ ] **Step 5.3: Collect condition from modal and store on connection**

In `app/javascript/controllers/property_editor/branch_manager.js`, in `addBranchFromModal`, add condition extraction:

After reading `branchValue`:
```javascript
// Extract condition fields
const conditionLeft  = modal.querySelector("[data-branch-condition-left]")?.value?.trim()
const conditionOp    = modal.querySelector("[data-branch-condition-op]")?.value || "=="
const conditionRight = modal.querySelector("[data-branch-condition-right]")?.value?.trim()

const condition = (conditionLeft && conditionRight)
  ? { type: "single", leftOperand: conditionLeft, operator: conditionOp, rightOperand: conditionRight }
  : (conditionLeft && ["is_empty", "is_not_empty"].includes(conditionOp))
    ? { type: "single", leftOperand: conditionLeft, operator: conditionOp, rightOperand: "" }
    : null
```

When creating the connection, pass condition to the canvas controller so it stores it on the connection JSON. In `_createBranchElement`, also update the outgoing connection from the Decision element by finding it via the canvas and setting `connection.condition = condition`.

The canvas element representing the connection needs a `condition` property. After creating the branch element, find the connection from the Decision node to this branch element and set its condition:

```javascript
if (condition && this.controller.canvas) {
  const canvas = this.controller.canvas
  const decisionEl = this.controller.currentElement
  // Find the connection that was just created to branchElementId
  const conn = canvas.connections.find(c => c.from === decisionEl.id && c.to === branchElementId)
  if (conn) conn.condition = condition
}
```

- [ ] **Step 5.4: Display condition in branch item template**

In `buildBranchItemTemplate`, add condition display. After the label/description display:

```javascript
// Add condition badge if present
const conditionBadge = branch.condition
  ? `<span class="ml-2 text-xs font-mono text-blue-600 bg-blue-50 px-1.5 py-0.5 rounded">
       if ${branch.condition.leftOperand} ${branch.condition.operator} ${branch.condition.rightOperand || ''}
     </span>`
  : ''
```

Include `conditionBadge` in the rendered HTML for the branch item.

- [ ] **Step 5.5: Save condition to connection when saving the flowchart**

The canvas already saves connections as part of the flowchart configuration JSON. The condition property on the connection object will be included in the JSON serialization automatically since the canvas serializes connections as plain objects.

Verify by testing: Create a Decision with a conditional branch, save the flowchart, check the stored configuration JSON includes `connections[].condition`.

- [ ] **Step 5.6: Commit**

```bash
cd /opt/milestone/anysys && git add app/javascript/controllers/property_editor/ && git commit -m "feat: add condition configuration per branch in property editor UI"
```

---

## Task 6: Wire up spec coverage for branch routing integration

**Files:**
- Create: `spec/services/activity_generator_integration_spec.rb`

- [ ] **Step 6.1: Write integration spec that generates and executes a branching activity**

```ruby
# spec/services/activity_generator_integration_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ActivityGenerator integration: branch routing" do
  let(:elements) do
    [
      { "id" => "s1", "type" => "start", "label" => "Start", "properties" => {} },
      { "id" => "d1", "type" => "decision", "label" => "Check amount",
        "properties" => {
          "condition" => {
            "type" => "single",
            "leftOperand" => "ctx.amount",
            "operator" => ">",
            "rightOperand" => "100"
          }
        }
      },
      { "id" => "a1", "type" => "process", "label" => "High value",
        "properties" => { "steps" => [{ "action" => "assign_value",
                                         "config" => { "targetVar" => "result", "valueType" => "string",
                                                        "stringValue" => "high" } }] }
      },
      { "id" => "b1", "type" => "process", "label" => "Low value",
        "properties" => { "steps" => [{ "action" => "assign_value",
                                         "config" => { "targetVar" => "result", "valueType" => "string",
                                                        "stringValue" => "low" } }] }
      },
      { "id" => "e1", "type" => "end", "label" => "End" }
    ]
  end

  let(:connections) do
    [
      { "id" => "c1", "from" => "s1", "to" => "d1" },
      { "id" => "c2", "from" => "d1", "to" => "a1", "label" => "Yes" },
      { "id" => "c3", "from" => "d1", "to" => "b1", "label" => "No" },
      { "id" => "c4", "from" => "a1", "to" => "e1" },
      { "id" => "c5", "from" => "b1", "to" => "e1" }
    ]
  end

  let(:flowchart) do
    instance_double(Flowchart,
      name: "AmountCheck",
      elements: elements,
      connections: connections,
      entity: nil,
      type_shared?: false,
      type_customer_specific?: true
    )
  end

  let(:activity_code) { ActivityGenerator.new(flowchart).generate }

  it "generates valid Ruby code" do
    expect { eval(activity_code) }.not_to raise_error  # rubocop:disable Security/Eval
  end

  context "when amount > 100" do
    it "executes the high-value branch" do
      eval(activity_code)  # rubocop:disable Security/Eval
      klass = Object.const_get("AmountCheckActivity")
      signal, (ctx, _) = klass.call(amount: 150)
      expect(ctx[:result]).to eq("high")
    end
  end

  context "when amount <= 100" do
    it "executes the low-value branch" do
      eval(activity_code)  # rubocop:disable Security/Eval
      klass = Object.const_get("AmountCheckActivity")
      signal, (ctx, _) = klass.call(amount: 50)
      expect(ctx[:result]).to eq("low")
    end
  end
end
```

- [ ] **Step 6.2: Run integration spec**

```bash
cd /opt/milestone/anysys && bundle exec rspec spec/services/activity_generator_integration_spec.rb --no-color 2>&1 | tail -30
```
Expected: All pass.

- [ ] **Step 6.3: Run full test suite**

```bash
cd /opt/milestone/anysys && bundle exec rspec --no-color 2>&1 | tail -30
```
Expected: No new failures.

- [ ] **Step 6.4: Commit**

```bash
cd /opt/milestone/anysys && git add spec/services/activity_generator_integration_spec.rb && git commit -m "test: add integration spec for branching activity execution"
```

---

## Task 7: Decision element topology — handle nested decisions (robustness)

The `FlowchartTopologyAnalyzer` assigns a single guard per node based on the first Decision found. For nested decisions (a decision inside a branch), the inner decision nodes need their own route index. The current implementation handles this through the `decision_indices` counter which increments per Decision found.

- [ ] **Step 7.1: Write test for nested Decision routing**

```ruby
# Add to spec/services/flowchart_topology_analyzer_spec.rb

context "with nested Decision elements" do
  let(:nested_elements) do
    [
      { "id" => "s1", "type" => "start" },
      { "id" => "d1", "type" => "decision", "label" => "Outer" },
      { "id" => "d2", "type" => "decision", "label" => "Inner" },
      { "id" => "a1", "type" => "process", "label" => "A" },
      { "id" => "b1", "type" => "process", "label" => "B" },
      { "id" => "c1", "type" => "process", "label" => "C" },
      { "id" => "m1", "type" => "process", "label" => "Merge" },
      { "id" => "e1", "type" => "end" }
    ]
  end
  let(:nested_connections) do
    [
      { "id" => "x1", "from" => "s1", "to" => "d1" },
      { "id" => "x2", "from" => "d1", "to" => "d2" },
      { "id" => "x3", "from" => "d1", "to" => "c1" },
      { "id" => "x4", "from" => "d2", "to" => "a1" },
      { "id" => "x5", "from" => "d2", "to" => "b1" },
      { "id" => "x6", "from" => "a1", "to" => "m1" },
      { "id" => "x7", "from" => "b1", "to" => "m1" },
      { "id" => "x8", "from" => "c1", "to" => "m1" },
      { "id" => "x9", "from" => "m1", "to" => "e1" }
    ]
  end

  subject(:result) do
    described_class.new(nested_elements, nested_connections).analyze
  end

  it "assigns distinct route indices to outer and inner decisions" do
    expect(result.decision_indices["d1"]).not_to eq(result.decision_indices["d2"])
  end

  it "guards inner-branch nodes with the inner decision's route index" do
    inner_idx = result.decision_indices["d2"]
    guard = result.node_guards["a1"]
    expect(guard[:decision_id]).to eq("d2")
    expect(guard[:branch]).to eq(:branch_0)
  end
end
```

- [ ] **Step 7.2: Run the test to confirm it passes**

```bash
cd /opt/milestone/anysys && bundle exec rspec spec/services/flowchart_topology_analyzer_spec.rb --no-color 2>&1 | tail -20
```

- [ ] **Step 7.3: Commit if tests pass**

```bash
cd /opt/milestone/anysys && git add spec/services/flowchart_topology_analyzer_spec.rb && git commit -m "test: add nested Decision topology coverage"
```

---

## Self-Review Checklist

- [x] **Spec coverage**: Tasks 1, 2, 4, 6 have complete specs. Task 3 has a documented request spec. Task 5 (JS) doesn't have automated tests (Capybara tests could be added later but are out of scope).
- [x] **No placeholders**: All code blocks contain real implementations, no TBD.
- [x] **Type consistency**: `ctx[:_route_0]` naming used consistently in ActivityGenerator, DecisionGenerator, SwitchGenerator, and test assertions. `node_guards[id]` returns `{ decision_id:, branch: }` hash throughout.
- [x] **Spec coverage for new spec**: `FlowchartTopologyAnalyzer` has full spec; `ActivityGenerator` branch routing has spec; `PublicPagesController` submit has request spec; integration spec exercises the full chain.
- [x] **Missing gap check**: The design doc lists EntityContractFactory — this already exists as `EntityEntryContract`. No new service needed.
- [x] **Merge point detection**: The `find_convergence_node` uses BFS intersection which handles diamond-shaped graphs correctly.
