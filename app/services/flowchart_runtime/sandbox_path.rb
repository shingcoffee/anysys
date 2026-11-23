# frozen_string_literal: true

module FlowchartRuntime
  # Sandboxed path helpers for flowchart file steps. Only basename filenames
  # under an allow-listed tmp root are permitted — never free-text paths.
  module SandboxPath
    class Error < StandardError; end

    GENERATED_ROOT  = "tmp/flowchart_generated"
    EXTRACT_ROOT    = "tmp/flowchart_extracts"
    DOWNLOAD_ROOT   = "tmp/flowchart_downloads"

    module_function

    def generated_path(filename)
      join_under(GENERATED_ROOT, filename)
    end

    def extract_dir(subdir = nil)
      root = Rails.root.join(EXTRACT_ROOT)
      FileUtils.mkdir_p(root)
      return root.to_s if subdir.blank?

      join_under(EXTRACT_ROOT, subdir)
    end

    def download_path(filename = nil)
      name = filename.presence || "#{SecureRandom.uuid}.bin"
      join_under(DOWNLOAD_ROOT, name)
    end

    def join_under(root_rel, filename)
      base = File.basename(filename.to_s)
      raise Error, "filename is required" if base.blank? || base == "." || base == ".."
      raise Error, "unsafe filename" if base != filename.to_s.strip || base.include?("\0")

      root = Rails.root.join(root_rel)
      FileUtils.mkdir_p(root)
      path = root.join(base)
      expanded = File.expand_path(path.to_s)
      root_expanded = File.expand_path(root.to_s)
      unless expanded == root_expanded || expanded.start_with?(root_expanded + File::SEPARATOR)
        raise Error, "path escapes sandbox"
      end

      path.to_s
    end
    module_function :join_under
  end
end
