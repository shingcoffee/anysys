# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module FileOperations
        class DownloadFileGenerator < BaseGenerator
          CHECKSUM_RE = /\A((sha256|md5):)?[0-9a-fA-F]{32,64}\z/

          generator_metadata do
            description "Downloads a file over HTTPS from an allow-listed public URL (SSRF-blocked by " \
                        "OutboundHttp) into ctx as a file payload {filename, content, content_type}. Use " \
                        "this to fetch a vendor CSV or ZIP for bulk_import or decompress_files. Prefer " \
                        "urlVariable when the URL comes from a record; url is a static fallback. Writes " \
                        "resultVar. Optional Content-Type allow-list, SHA-256/MD5 checksum, 25 MB size " \
                        "cap, redirects, retries, and a circuit breaker. Fails with download_file.failed " \
                        "or HTTP/transport codes when the host is blocked, the type/checksum/size is wrong, " \
                        "or the request errors."
            category :file_operations
            version "4.0.0"
            presentation icon: "M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4",
                         color: "blue", single_use: false, privileged: false
          end

          config_schema do
            literal :url, example: "https://example.com/file.csv", placeholder: true,
                    description: "Static HTTPS URL to GET, for example https://files.example.com/orders.csv. " \
                                 "Ignored when urlVariable is set and that ctx value is present. Private hosts are blocked."
            input :urlVariable,
                  description: "Ctx path that holds the download URL, for example invoice.file_url. " \
                               "When set, it is tried first; url is the fallback if that path is blank."
            output :resultVar, default: "file_content",
                   description: "Ctx variable that receives the file payload {filename, content, content_type} " \
                                "for generate-file consumers such as upload_file, compress_files, or bulk_import."
            integer :maxSizeBytes, min: 1, max: 104_857_600, group: :advanced,
                    description: "Reject a response larger than this many bytes (1-104857600). " \
                                 "Default is 25 MB, hard-capped at 100 MB, streamed so an oversized body is aborted mid-transfer."
            flag :followRedirects, default: true,
                 description: "When true (default), follow HTTP redirects up to maxRedirects. Turn off to refuse any redirect."
            integer :maxRedirects, min: 0, max: 10, default: 3, visible: { followRedirects: true },
                    description: "Maximum redirects to follow when followRedirects is on (0-10, default 3)."
            mapping :headers, key: :literal, value: :literal, default: [],
                    description: "Extra request headers as name/value pairs, for example Accept mapped to text/csv. " \
                                 "Do not put secrets in the flowchart; use a ctx value only if the secret is already in ctx."
            list :allowedContentTypes, item: :literal, default: [], group: :advanced,
                 description: "Allowed response Content-Type values such as text/csv or application/zip. " \
                              "Empty allows any type. A mismatch fails the step."
            literal :validateChecksum, placeholder: true,
                    description: "Optional digest of the body: sha256: plus 64 hex chars, md5: plus 32 hex chars, " \
                                 "or a bare 32/64 hex string. Mismatch fails the step."
            timeouts open: 3, read: 7
            transport_retry idempotent_when: {}
            circuit_breaker_option

            validate do |_cfg, errors|
              if value(:url).to_s.strip.empty? && value(:urlVariable).to_s.strip.empty?
                errors.add(:url, :required)
              end
              checksum = value(:validateChecksum).to_s.strip
              if checksum.present? && !CHECKSUM_RE.match?(checksum)
                errors.add(:validateChecksum, :invalid_checksum)
              end
            end
          end

          def generate_body
            body(
              attempt('"download_file.failed"', FlowchartRuntime::FileDownload::Error) do
                [
                  "download = #{fetch_call}",
                  "next false if download == false",
                  assign(:resultVar, "download")
                ]
              end
            )
          end

          private

          def fetch_call
            args = [
              "ctx",
              url_source,
              optional_kw("headers", read(:headers), "{}"),
              optional_kw("open_timeout", read(:connectTimeout), "3"),
              optional_kw("read_timeout", read(:readTimeout), "7"),
              optional_kw("retries", retries_source, "0"),
              optional_kw("breaker", breaker_source, "nil"),
              optional_kw("follow_redirects", read(:followRedirects), "true"),
              (optional_kw("max_redirects", read(:maxRedirects), "3") if value(:followRedirects)),
              optional_kw("max_bytes", optional_int(:maxSizeBytes), "nil"),
              optional_kw("checksum", checksum_source, "nil"),
              optional_kw("allowed_content_types", read(:allowedContentTypes), "[]")
            ].compact
            "FlowchartRuntime::FileDownload.fetch(#{args.join(', ')})"
          end

          def url_source
            if value(:urlVariable).present? && value(:url).to_s.present?
              "(#{read(:urlVariable)}.presence || #{read(:url)})"
            elsif value(:urlVariable).present?
              read(:urlVariable)
            else
              read(:url)
            end
          end

          def retries_source
            value(:retryOnTransportError) ? read(:retryAttempts) : "0"
          end

          def breaker_source
            return "nil" unless value(:circuitBreaker)

            "{ name: #{read(:breakerName)}, threshold: #{read(:failureThreshold)}, reset_seconds: #{read(:resetTimeoutSeconds)} }"
          end

          def checksum_source
            value(:validateChecksum).to_s.present? ? read(:validateChecksum) : "nil"
          end

          def optional_int(field)
            value(field).nil? ? "nil" : read(field)
          end

          def optional_kw(name, source, default)
            "#{name}: #{source}" unless source == default
          end
        end
      end
    end
  end
end
