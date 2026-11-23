# frozen_string_literal: true

module Operations
  class Context < Struct.new(
    :customer, :actor, :channel, :conversation, :generation,
    :idempotency_key, :dry_run, :confirmed, :around_write,
    keyword_init: true
  )
    CHANNELS = %w[assistant api system].freeze

    def initialize(**)
      super
      self.channel = channel.to_s.presence || "system"
      self.dry_run = false if dry_run.nil?
      self.confirmed = false if confirmed.nil?
      self.around_write ||= ->(&block) { block.call }
    end
  end
end
