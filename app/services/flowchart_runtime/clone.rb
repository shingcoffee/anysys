# frozen_string_literal: true

require "active_support/core_ext/object/deep_dup"

module FlowchartRuntime
  module Clone
    class Error < StandardError; end

    module_function

    def copy(source, deep: false, exclude: [])
      raise Error, "source is required" if source.nil?

      clone = deep ? source.deep_dup : source.dup
      excluded = Array(exclude).map(&:to_s).reject(&:blank?)
      excluded.each do |name|
        writer = "#{name}="
        if clone.respond_to?(writer)
          clone.public_send(writer, nil)
        elsif clone.respond_to?(:delete)
          clone.delete(name) || clone.delete(name.to_sym)
        end
      end
      attach_files(source, clone, excluded) if source.is_a?(EntityEntry)
      clone
    end

    # dup drops attachments; the copy shares the source's stored files (a
    # blob another record still holds is never purged).
    def attach_files(source, clone, excluded)
      source.class.file_attributes.each_key do |slug|
        next if excluded.include?(slug)

        blobs = source.file_blobs(slug)
        clone.public_send("#{slug}=", blobs) if blobs.any?
      end
    end
    private_class_method :attach_files
  end
end
