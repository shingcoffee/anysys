# frozen_string_literal: true

module FlowchartRuntime
  # Tenant-scoped, sandboxed append-only log sink for the `log` step's
  # "file" logger.
  #
  # Mirrors FlowchartRuntime::SandboxPath (basename-only under an allow-listed
  # tmp root) and FlowchartRuntime::CacheKey (tenant identity is mandatory, not
  # optional). Without it the generator interpolated the raw `filePath` config
  # straight into `File.open`, which is both a cross-tenant leak — every
  # customer appending to one shared file — and an arbitrary-path write
  # (`../../config/master.key`).
  #
  # Fails closed: a missing tenant or an unsafe filename raises rather than
  # silently degrading to an unscoped path.
  module LogFile
    class Error < StandardError; end

    ROOT = "tmp/flowchart_logs"
    DEFAULT_FILENAME = "application.log"

    module_function

    # Absolute path of the tenant's log file. Only a basename is honored; any
    # directory component in +filename+ is discarded before validation.
    def path_for(tenant_namespace, filename = nil)
      tenant = sanitize_segment(tenant_namespace.to_s.strip, "tenant namespace")
      base   = File.basename(filename.to_s.strip)
      base   = DEFAULT_FILENAME if base.empty? || base == "." || base == ".."
      name   = sanitize_segment(base, "log filename")

      dir = Rails.root.join(ROOT, tenant)
      FileUtils.mkdir_p(dir)
      path = dir.join(name)

      root_expanded = File.expand_path(dir.to_s)
      expanded = File.expand_path(path.to_s)
      raise Error, "path escapes sandbox" unless expanded.start_with?(root_expanded + File::SEPARATOR)

      expanded
    end

    # Appends one line to the tenant's log file.
    def append(tenant_namespace, filename, line)
      File.open(path_for(tenant_namespace, filename), "a") { |f| f.puts(line) }
      true
    end

    def sanitize_segment(value, label)
      raise Error, "#{label} is required" if value.empty?
      raise Error, "unsafe #{label}" if value.include?("\0") || value.include?("/") ||
                                        value.include?("\\") || value.include?("..")
      raise Error, "unsafe #{label}" unless value.match?(/\A[A-Za-z0-9._-]+\z/)

      value
    end
  end
end
