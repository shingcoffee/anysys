# frozen_string_literal: true

module FlowchartDefinitions
  # Pure function: rewrite a canvas configuration so every process has at most
  # one step. Shared by the assistant Normalizer and the data rake task.
  class ProcessSplitter
    ROW_GAP = 100

    def self.call(configuration)
      new(configuration).call
    end

    def initialize(configuration)
      @source = configuration
    end

    def call
      return @source unless @source.is_a?(Hash)

      config = @source.deep_stringify_keys.deep_dup
      elements = Array(config["elements"])
      connections = Array(config["connections"])
      targets = elements.select { |element| multi_action_process?(element) }
                        .sort_by { |element| -element["y"].to_i }

      targets.each { |element| split_process!(element, elements, connections) }
      config["elements"] = elements
      config["connections"] = connections
      config
    end

    def self.multi_action?(configuration)
      return false unless configuration.is_a?(Hash)

      Array(configuration["elements"]).any? { |element| process_step_count(element) > 1 }
    end

    def self.process_step_count(element)
      return 0 unless element.is_a?(Hash) && element["type"].to_s == "process"

      steps_of(element).size
    end

    def self.steps_of(element)
      return [] unless element.is_a?(Hash)

      properties = element["properties"]
      if properties.is_a?(Hash) && properties["steps"].is_a?(Array)
        properties["steps"]
      elsif element["steps"].is_a?(Array)
        element["steps"]
      else
        []
      end
    end

    private

    def multi_action_process?(element)
      self.class.process_step_count(element) > 1
    end

    def steps_of(element)
      self.class.steps_of(element)
    end

    def set_steps!(element, steps)
      element["properties"] = {} unless element["properties"].is_a?(Hash)
      element["properties"]["steps"] = steps
      element.delete("steps")
    end

    def split_process!(element, elements, connections)
      steps = steps_of(element).map { |step| step.is_a?(Hash) ? step.deep_dup : step }
      extras = steps.drop(1)
      return if extras.empty?

      origin_y = element["y"].to_i
      shift = extras.size * ROW_GAP
      existing_ids = elements.to_set { |el| el["id"] }

      set_steps!(element, [steps.first])

      elements.each do |el|
        next if el.equal?(element)
        next unless el["y"].to_i > origin_y

        el["y"] = el["y"].to_i + shift
      end

      new_ids = []
      extras.each_with_index do |step, index|
        new_id = unique_id("#{element["id"]}_#{index + 2}", existing_ids)
        existing_ids << new_id
        new_ids << new_id
        action = step.is_a?(Hash) ? step["action"].to_s : ""
        new_element = {
          "id" => new_id,
          "type" => "process",
          "x" => element["x"],
          "y" => origin_y + ((index + 1) * ROW_GAP),
          "width" => element["width"],
          "height" => element["height"],
          "label" => ActionLabel.for(action),
          "properties" => {
            "inputs" => [],
            "outputs" => [],
            "steps" => [step]
          }
        }
        insert_after = index.zero? ? element : elements.find { |el| el["id"] == new_ids[index - 1] }
        elements.insert(elements.index(insert_after) + 1, new_element)
      end

      chain = [element["id"], *new_ids]
      connections.each do |connection|
        connection["from"] = chain.last if connection["from"] == element["id"]
      end

      existing_conn_ids = connections.to_set { |connection| connection["id"] }
      chain.each_cons(2) do |from, to|
        conn_id = unique_id("c_#{from}_#{to}", existing_conn_ids)
        existing_conn_ids << conn_id
        connections << {
          "id" => conn_id,
          "from" => from,
          "to" => to,
          "fromPosition" => "bottom",
          "toPosition" => "top"
        }
      end
    end

    def unique_id(preferred, existing)
      return preferred unless existing.include?(preferred)

      if preferred =~ /\A(.*)_(\d+)\z/
        prefix = Regexp.last_match(1)
        number = Regexp.last_match(2).to_i + 1
        number += 1 while existing.include?("#{prefix}_#{number}")
        "#{prefix}_#{number}"
      else
        number = 2
        number += 1 while existing.include?("#{preferred}_#{number}")
        "#{preferred}_#{number}"
      end
    end
  end
end
