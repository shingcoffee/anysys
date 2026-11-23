# frozen_string_literal: true

class ActivityGenerator
  # Pure planner for Railway wiring. Input is the DFS-ordered step list for one
  # scope; output is magnetic/output fragments plus the CANVAS routes/ends maps.
  # Rules match spec A3, with back-edges into a loop header always explicit.
  class WiringPlanner
    StepPlan = Struct.new(:id, :magnetic, :outputs, keyword_init: true)
    Result = Struct.new(:step_plans, :routes, :ends, keyword_init: true)

    def initialize(descriptors:, decision_branches:, stepless_end_ids:, terminal_targets: nil)
      @descriptors = Array(descriptors)
      @decision_branches = (decision_branches || {}).transform_keys(&:to_sym)
      @stepless_end_ids = Array(stepless_end_ids).map(&:to_s).to_set
      @terminal_targets = Array(terminal_targets || stepless_end_ids).map(&:to_s).to_set
      @by_id = @descriptors.index_by { |descriptor| descriptor[:id].to_sym }
      @element_to_step = @descriptors.to_h { |descriptor| [descriptor[:element_id].to_s, descriptor[:id].to_sym] }
      @index_by_id = @descriptors.each_with_index.to_h { |descriptor, index| [descriptor[:id].to_sym, index] }
    end

    def call
      magnetics = compute_magnetics
      plans = @descriptors.each_with_index.map do |descriptor, index|
        id = descriptor[:id].to_sym
        StepPlan.new(id: id, magnetic: magnetics[index], outputs: outputs_for(descriptor, index, magnetics))
      end
      Result.new(step_plans: plans, routes: routes_map, ends: ends_map)
    end

    private

    def compute_magnetics
      @descriptors.each_with_index.map do |descriptor, index|
        next true if index.zero?

        previous = @descriptors[index - 1]
        next false if previous[:kind] == :decision
        next false unless successor_step_ids(previous).include?(descriptor[:id].to_sym)

        true
      end
    end

    def successor_step_ids(descriptor)
      return loop_success_ids(descriptor) if descriptor[:kind] == :loop

      Array(descriptor[:successors]).filter_map { |target| resolve_step(target) }
    end

    def loop_success_ids(descriptor)
      body = resolve_step(descriptor[:body_id])
      body ? [body] : []
    end

    def resolve_step(target)
      return if target.nil?
      return target.to_sym if target.is_a?(Symbol) && @by_id.key?(target.to_sym)

      @element_to_step[target.to_s]
    end

    def stepless_or_terminal?(target)
      @terminal_targets.include?(target.to_s) || @stepless_end_ids.include?(target.to_s)
    end

    def outputs_for(descriptor, index, magnetics)
      return decision_outputs(descriptor) if descriptor[:kind] == :decision
      return loop_outputs(descriptor, index, magnetics) if descriptor[:kind] == :loop

      successors = Array(descriptor[:successors])
      if successors.empty? || successors.all? { |target| stepless_or_terminal?(target) }
        return index == @descriptors.size - 1 ? [] : [["Output(:success)", "End(:success)"]]
      end

      target = successors.first
      dest_step = resolve_step(target)
      return [["Output(:success)", dest_step ? "Id(:#{dest_step})" : "End(:success)"]] if backedge?(descriptor, dest_step)

      next_descriptor = @descriptors[index + 1]
      implicit = next_descriptor && dest_step == next_descriptor[:id].to_sym && magnetics[index + 1]
      return [] if implicit

      [["Output(:success)", dest_step ? "Id(:#{dest_step})" : "End(:success)"]]
    end

    def backedge?(descriptor, dest_step)
      return false unless dest_step

      dest_index = @index_by_id[dest_step]
      src_index = @index_by_id[descriptor[:id].to_sym]
      dest_index && src_index && dest_index < src_index
    end

    def loop_outputs(descriptor, index, magnetics)
      outputs = []
      body = resolve_step(descriptor[:body_id])
      if body
        next_descriptor = @descriptors[index + 1]
        implicit = next_descriptor && body == next_descriptor[:id].to_sym && magnetics[index + 1]
        outputs << ["Output(:success)", "Id(:#{body})"] unless implicit
      else
        outputs << ["Output(:success)", "Track(:failure)"]
      end
      signal = descriptor[:done_signal] || "Routes::Loop::Done"
      outputs << ["Output(#{signal}, :done)", wire_target(descriptor[:exit_id])]
      outputs
    end

    def decision_outputs(descriptor)
      branches_for(descriptor).map { |branch|
        ["Output(#{branch[:signal]}, :#{branch[:semantic]})", wire_target(branch[:target])]
      } + [["Output(:success)", "Track(:failure)"]]
    end

    def wire_target(target)
      return "End(:success)" if target.nil? || stepless_or_terminal?(target)

      step = resolve_step(target)
      step ? "Id(:#{step})" : "End(:success)"
    end

    def branches_for(descriptor)
      @decision_branches[descriptor[:id].to_sym] || []
    end

    def routes_map
      map = {}
      @decision_branches.each do |step_id, branches|
        next if branches.blank?

        map[step_id.to_sym] = branches.to_h { |branch| [branch[:semantic].to_sym, branch[:connection_id].to_s] }
      end
      @descriptors.each do |descriptor|
        next unless descriptor[:kind] == :loop && descriptor[:done_connection_id]

        map[descriptor[:id].to_sym] = { done: descriptor[:done_connection_id].to_s }
      end
      map
    end

    def ends_map
      @descriptors.each_with_object({}) do |descriptor, map|
        id = descriptor[:id].to_sym
        if descriptor[:kind] == :decision
          branches_for(descriptor).each do |branch|
            target = branch[:target].to_s
            next unless @stepless_end_ids.include?(target)

            (map[id] ||= {})[branch[:semantic].to_sym] = target
          end
        elsif descriptor[:kind] == :loop
          target = descriptor[:exit_id].to_s
          (map[id] ||= {})[:done] = target if @stepless_end_ids.include?(target)
        else
          Array(descriptor[:successors]).each do |target|
            next unless @stepless_end_ids.include?(target.to_s)

            (map[id] ||= {})[:success] = target.to_s
          end
        end
      end
    end
  end
end
