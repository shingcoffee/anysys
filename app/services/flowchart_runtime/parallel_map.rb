# frozen_string_literal: true

require "parallel"

module FlowchartRuntime
  # FlowchartRuntime::ParallelMap
  #
  # Thin wrapper around the parallel gem for flowchart parallel_for_each and
  # map_collection step generators.
  module ParallelMap
    class Error < StandardError; end

    MAX_THREADS = 16

    module_function

    # @param collection [Enumerable]
    # @param in_threads [Integer]
    # @yieldparam item [Object]
    # @return [Array]
    # @raise  [FlowchartRuntime::ParallelMap::Error]
    def map(collection, in_threads:, &block)
      threads = validate_inputs!(collection, in_threads, block)
      Parallel.map(collection, in_threads: threads, &block)
    rescue Parallel::DeadWorker, Parallel::UndumpableException => e
      raise Error, e.message
    end

    # @param collection [Enumerable]
    # @param in_threads [Integer]
    # @yieldparam item [Object]
    # @return [nil]
    # @raise  [FlowchartRuntime::ParallelMap::Error]
    def each(collection, in_threads:, &block)
      threads = validate_inputs!(collection, in_threads, block)
      Parallel.each(collection, in_threads: threads, &block)
    rescue Parallel::DeadWorker, Parallel::UndumpableException => e
      raise Error, e.message
    end

    def validate_inputs!(collection, in_threads, block)
      raise Error, "collection is required" unless collection.respond_to?(:each)
      raise Error, "block is required" unless block

      threads = Integer(in_threads, exception: false)
      raise Error, "in_threads must be positive" unless threads&.positive?
      raise Error, "in_threads exceeds maximum of #{MAX_THREADS}" if threads > MAX_THREADS

      threads
    end
    private_class_method :validate_inputs!
  end
end
