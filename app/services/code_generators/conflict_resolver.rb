# frozen_string_literal: true

require "digest"
require "set"

module CodeGenerators
  # ConflictResolver — element-level ctx-key collision detector.
  #
  # Input shape: an array of element descriptors (hashes with string or
  # symbol keys, accepted interchangeably). Each descriptor carries:
  #
  #   id      — element id (string).
  #   outputs — array of { pin: "<effective_emitted_key>" } entries. The
  #             caller (ActivityGenerator) supplies already-effective keys:
  #             for process elements it has already applied the shipped
  #             per-step rename, so a step that now emits :model_a3f2
  #             shows up here as { pin: "model_a3f2" }. For non-process
  #             elements the pin is simply the literal ctx key the
  #             generator writes.
  #
  # Output: rename_map, a two-level hash
  #   { element_id => { pin_name => renamed_key }, ... }
  # Elements with no colliding outputs get no entry.
  #
  # A pin emitted by >=2 elements is renamed on an element only when
  # another writer of that pin is an ancestor in the dataflow graph
  # (loop back-edges excluded). Writers on exclusive branches, and
  # terminal Ends that do not dominate each other, keep the original key.
  #
  # Rename format: "<pin>_<sha1(element_id:pin)[0..3]>". If two
  # (element_id, pin) pairs share the same 4-char prefix within this
  # flowchart, ALL emitters of THAT colliding pin fall back to 6 chars.
  class ConflictResolver
    def self.call(elements, topo_order: nil, ancestors: nil)
      new(elements, topo_order: topo_order, ancestors: ancestors).call
    end

    def initialize(elements, topo_order: nil, ancestors: nil)
      @elements = Array(elements).map { |e| normalize(e) }
      @topo_order = topo_order || @elements.map { |e| e[:id] }
      @id_to_topo_index = @topo_order.each_with_index.to_h
      @id_to_element_index = @elements.each_with_index.to_h { |el, i| [el[:id], i] }
      @ancestors = normalize_ancestors(ancestors)
    end

    def call
      emitters = Hash.new { |h, k| h[k] = [] }
      seen = {}
      @elements.each do |el|
        el[:outputs].each do |o|
          pin = (o[:pin] || o["pin"]).to_s
          next if pin.empty?
          # Dedup (element_id, pin) pairs — an element listing the same
          # output twice should not nominate itself as a colliding emitter.
          key = [el[:id], pin]
          next if seen[key]
          seen[key] = true
          emitters[pin] << key
        end
      end

      rename_map = {}
      emitters.each do |_key, refs|
        next if refs.size < 2

        writer_ids = refs.map(&:first).to_set
        refs_to_rename = refs.select { |(id, _pin)| ancestor_writer?(id, writer_ids) }
        next if refs_to_rename.empty?

        refs_to_rename = refs_to_rename.sort_by do |(id, _pin)|
          [@id_to_topo_index[id] || Float::INFINITY, @id_to_element_index[id] || Float::INFINITY]
        end

        suffix_length = collision_free_suffix_length(refs_to_rename)
        refs_to_rename.each do |(id, pin)|
          rename_map[id] ||= {}
          rename_map[id][pin] = "#{pin}_#{sha1_suffix(id, pin, suffix_length)}"
        end
      end

      rename_map
    end

    private

    def normalize(el)
      {
        id:      (el[:id] || el["id"]).to_s,
        outputs: Array(el[:outputs] || el["outputs"])
      }
    end

    def normalize_ancestors(ancestors)
      (ancestors || {}).each_with_object({}) do |(id, ids), acc|
        acc[id.to_s] = Array(ids).map(&:to_s).to_set
      end
    end

    def ancestor_writer?(id, writer_ids)
      others = writer_ids - [id]
      @ancestors.fetch(id, Set.new).intersect?(others)
    end

    # SHA1 is 40 hex chars total; we walk a progression of prefix sizes and
    # return the shortest one that disambiguates all renamed pins. The final
    # 40 entry is the full digest — if two (id, pin) pairs collide on a full
    # SHA1 we have bigger problems than naming.
    SUFFIX_LENGTH_PROGRESSION = [4, 6, 8, 12, 16, 40].freeze

    def collision_free_suffix_length(refs)
      SUFFIX_LENGTH_PROGRESSION.each do |length|
        prefixes = refs.map { |(id, pin)| sha1_suffix(id, pin, length) }
        return length if prefixes.uniq.length == prefixes.length
      end
      40
    end

    def sha1_suffix(id, pin, length)
      Digest::SHA1.hexdigest("#{id}:#{pin}")[0, length]
    end
  end
end
