# frozen_string_literal: true

require "bcrypt"
require "scrypt"
require "argon2"

module FlowchartRuntime
  # FlowchartRuntime::PasswordHash
  #
  # Thin wrapper around BCrypt, SCrypt, and Argon2 for flowchart hash-data
  # step generators. Owns allowed password algorithms and a single error type
  # (FlowchartRuntime::PasswordHash::Error) so generated step code never
  # rescues raw gem exceptions or conditionally skips required dependencies.
  module PasswordHash
    class Error < StandardError; end

    PASSWORD_ALGORITHMS = %w[bcrypt scrypt argon2].freeze
    DEFAULT_BCRYPT_COST = 12
    DEFAULT_SCRYPT_MAX_TIME = 0.2
    ARGON2_TIME_COSTS = (1..8)
    # Memory cost is log2 KiB; 17 (128 MiB per hash) keeps one step from exhausting a worker.
    ARGON2_MEMORY_COSTS = (8..17)

    module_function

    # @param algorithm [String] bcrypt, scrypt, or argon2
    # @param password  [String]
    # @param opts      [Hash] algorithm-specific options (cost, iterations, t_cost, …)
    # @return [String] encoded password hash
    # @raise  [FlowchartRuntime::PasswordHash::Error]
    def create(algorithm, password, **opts)
      algo = algorithm.to_s
      raise Error, "unsupported password algorithm" unless PASSWORD_ALGORITHMS.include?(algo)
      raise Error, "password is required" if password.nil?
      validate_options!(algo, opts)

      case algo
      when "bcrypt" then create_bcrypt(password, **opts)
      when "scrypt" then create_scrypt(password, **opts)
      when "argon2" then create_argon2(password, **opts)
      end
    rescue Argon2::ArgonHashFail, BCrypt::Errors::InvalidHash, BCrypt::Errors::InvalidCost,
           SCrypt::Errors::InvalidHash, SCrypt::Errors::InvalidSalt, SCrypt::Errors::InvalidSecret => e
      raise Error, e.message
    end

    def create_bcrypt(password, cost: DEFAULT_BCRYPT_COST, **_opts)
      BCrypt::Password.create(password.to_s, cost: cost.to_i)
    end

    def create_scrypt(password, iterations: nil, max_time: nil, max_mem: nil, **_opts)
      options = {}
      options[:max_time] = resolved_scrypt_max_time(iterations, max_time)
      options[:max_mem] = max_mem if max_mem
      SCrypt::Password.create(password.to_s, options)
    end

    def create_argon2(password, t_cost: nil, m_cost: nil, p_cost: nil, **_opts)
      options = {}
      options[:t_cost] = t_cost if t_cost
      options[:m_cost] = m_cost if m_cost
      options[:p_cost] = p_cost if p_cost
      Argon2::Password.create(password.to_s, options)
    end

    def resolved_scrypt_max_time(iterations, max_time)
      return max_time.to_f if max_time

      return DEFAULT_SCRYPT_MAX_TIME unless iterations

      # Map UI "iterations" to SCrypt's time budget (roughly 100k ≈ 0.2s).
      [iterations.to_f / 500_000.0, 0.01].max
    end

    def validate_options!(algorithm, options)
      case algorithm
      when "bcrypt"
        cost = Integer(options.fetch(:cost, DEFAULT_BCRYPT_COST), exception: false)
        unless cost && (BCrypt::Engine::MIN_COST..BCrypt::Engine::MAX_COST).cover?(cost)
          raise Error, "invalid bcrypt cost"
        end
      when "argon2"
        argon2_cost!(options[:t_cost], ARGON2_TIME_COSTS, "invalid argon2 time cost")
        argon2_cost!(options[:m_cost], ARGON2_MEMORY_COSTS, "invalid argon2 memory cost")
      end
    end

    def argon2_cost!(value, range, message)
      return if value.nil?

      cost = Integer(value, exception: false)
      raise Error, message unless cost && range.cover?(cost)
    end
    private_class_method :resolved_scrypt_max_time, :validate_options!, :argon2_cost!
  end
end
