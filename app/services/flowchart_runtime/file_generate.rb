# frozen_string_literal: true

require "builder"
require "caxlsx"
require "csv"
require "json"
require "prawn"
require "stringio"

module FlowchartRuntime
  # FlowchartRuntime::FileGenerate
  #
  # Thin wrapper around builder, caxlsx, and prawn for flowchart generate_file
  # step generators. Owns a single error type so generated step code never
  # rescues raw gem exceptions.
  module FileGenerate
    class Error < StandardError; end

    PAGE_SIZES = {
      "letter" => "LETTER",
      "a4"     => "A4",
      "legal"  => "LEGAL"
    }.freeze
    PRAWN_ERRORS = Prawn::Errors.constants.filter_map do |name|
      error_class = Prawn::Errors.const_get(name)
      error_class if error_class.is_a?(Class) && error_class < StandardError
    end.freeze
    INVALID_WORKSHEET_NAME = %r{[\[\]*\/\\?:]}
    MAX_WORKSHEET_NAME_LENGTH = 31

    FILE_TYPES = %w[csv xlsx json txt].freeze
    LINE_ENDINGS = { "lf" => "\n", "crlf" => "\r\n" }.freeze

    module_function

    def apply(data, file_type:, columns: [], sheet_name: "Sheet1", auto_filter: false,
              pretty: false, line_ending: "lf", filename: nil, delimiter: ",",
              header_row: true, quote_strings: false, include_bom: true,
              nested_separator: ".", locale: nil)
      type = file_type.to_s
      raise Error, "unknown file type" unless FILE_TYPES.include?(type)

      rows = normalize_rows(data)
      locale = locale.presence || I18n.locale
      content = I18n.with_locale(locale) do
        case type
        when "csv"
          csv(
            data: rows, columns: columns, encoding: "utf-8", delimiter: delimiter,
            header_row: header_row, quote_strings: quote_strings, include_bom: include_bom,
            nested_separator: nested_separator, locale: locale
          )
        when "xlsx"
          xlsx(
            data: rows, columns: columns_as_key_value(columns), sheet_name: sheet_name,
            auto_filter: auto_filter, locale: locale
          )
        when "json"
          pretty ? JSON.pretty_generate(rows) : rows.to_json
        else
          Array(rows).map { |row| txt_line(row) }.join(LINE_ENDINGS.fetch(line_ending.to_s, "\n"))
        end
      end

      name = filename.to_s.presence || "export.#{type}"
      FilePayload.wrap(content, filename: name, content_type: FilePayload::CONTENT_TYPES[type])
    end

    def csv(data:, columns: [], encoding: "utf-8", delimiter: ",", header_row: true,
            quote_strings: false, include_bom: true, nested_separator: ".", locale: nil)
      rows = Array(data)
      normalized = localize_columns(normalize_csv_columns(columns), locale)
      body = CSV.generate(encoding: encoding.to_s, col_sep: delimiter.to_s, force_quotes: quote_strings) do |table|
        if normalized.any?
          table << normalized.map { |column| column[:header] } if header_row
          rows.each do |row|
            table << normalized.map { |column|
              format_cell(fetch_nested(row, column[:field], nested_separator), locale)
            }
          end
        elsif rows.first.is_a?(Hash)
          headers = rows.flat_map { |row| row.keys.map(&:to_s) }.uniq
          table << headers.map { |header| localize_header(header, locale) } if header_row
          rows.each { |row| table << headers.map { |header| format_cell(fetch_row_value(row, header), locale) } }
        else
          rows.each { |row| table << Array(row).map { |cell| format_cell(cell, locale) } }
        end
      end
      include_bom ? "\uFEFF#{body}" : body
    end

    # @param data         [Array<Hash>, Array] row collection
    # @param columns      [Array<Hash>] optional { "key" => header, "value" => field }
    # @param sheet_name   [String]
    # @param auto_filter  [Boolean]
    # @return [String] binary xlsx payload
    # @raise  [FlowchartRuntime::FileGenerate::Error]
    def xlsx(data:, columns: [], sheet_name: "Sheet1", auto_filter: false, locale: nil)
      validate_worksheet_name!(sheet_name)

      package = Axlsx::Package.new
      package.workbook.add_worksheet(name: sheet_name.to_s) do |sheet|
        normalized_columns = localize_xlsx_columns(normalize_columns(columns), locale)
        rows = Array(data)

        if normalized_columns.any?
          sheet.add_row normalized_columns.map { |c| c[:key] }
          rows.each do |row|
            sheet.add_row normalized_columns.map { |c| format_cell(fetch_row_value(row, c[:value]), locale) }
          end
        elsif rows.first.is_a?(Hash)
          headers = rows.flat_map(&:keys).map(&:to_s).uniq
          sheet.add_row headers.map { |header| localize_header(header, locale) }
          rows.each { |row| sheet.add_row headers.map { |h| format_cell(fetch_row_value(row, h), locale) } }
        else
          rows.each { |row| sheet.add_row Array(row).map { |cell| format_cell(cell, locale) } }
        end

        apply_auto_filter!(sheet) if auto_filter && sheet.rows.size > 1
      end
      package.to_stream.read
    rescue Zip::Error => e
      raise Error, e.message
    end

    # @param data       [Array<Hash>, Array] tabular or line content
    # @param page_size  [String] letter, a4, or legal
    # @return [String] binary pdf payload
    # @raise  [FlowchartRuntime::FileGenerate::Error]
    def pdf(data:, page_size: "letter")
      raise Error, "unsupported page size" unless PAGE_SIZES.key?(page_size.to_s)

      size = PAGE_SIZES.fetch(page_size.to_s)
      rows = Array(data)

      Prawn::Document.new(page_size: size) do |doc|
        if rows.all? { |row| row.is_a?(Hash) }
          headers = rows.flat_map(&:keys).map(&:to_s).uniq
          doc.text headers.join(" | ")
          rows.each do |row|
            doc.text headers.map { |h| fetch_row_value(row, h).to_s }.join(" | ")
          end
        else
          rows.each { |line| doc.text line.to_s }
        end
      end.render
    rescue *PRAWN_ERRORS => e
      raise Error, e.message
    end

    # @param data          [Array<Hash>] item collection
    # @param root_element  [String]
    # @return [String] xml payload
    # @raise  [FlowchartRuntime::FileGenerate::Error]
    def xml(data:, root_element: "root")
      raise Error, "root element is required" if root_element.to_s.empty?
      items = data.is_a?(Hash) ? [data] : Array(data)
      raise Error, "xml data items must be hashes" unless items.all? { |item| item.is_a?(Hash) }

      markup = Builder::XmlMarkup.new(indent: 2)
      markup.instruct!
      markup.tag!(root_element.to_s) do
        items.each do |item|
          markup.tag!("item") do
            item.each { |key, value| markup.tag!(key.to_s, value) }
          end
        end
      end
      markup.target!
    rescue Builder::IllegalBlockError => e
      raise Error, e.message
    end

    # @param content   [String] file body
    # @param filename  [String]
    # @return [ActiveStorage::Blob]
    # @raise  [FlowchartRuntime::FileGenerate::Error]
    def attach_active_storage(content, filename:)
      raise Error, "filename is required" if filename.to_s.empty?

      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(content.to_s),
        filename: filename.to_s
      )
    rescue ActiveStorage::IntegrityError, ActiveStorage::FileNotFoundError,
           ActiveRecord::ActiveRecordError => e
      raise Error, e.message
    end

    def normalize_csv_columns(columns)
      case columns
      when Hash
        columns.map { |key, value| { header: key.to_s, field: value.to_s } }
      when Array
        columns.filter_map do |column|
          next unless column.is_a?(Hash)

          header = column["key"] || column[:key] || column["header"] || column[:header]
          field = column["value"] || column[:value] || column["field"] || column[:field]
          next if header.nil?

          { header: header.to_s, field: field.to_s }
        end
      else
        []
      end
    end

    def columns_as_key_value(columns)
      normalize_csv_columns(columns).map { |column| { "key" => column[:header], "value" => column[:field] } }
    end

    def fetch_nested(row, field, separator)
      path = field.to_s
      return fetch_row_value(row, path) if separator.to_s.empty? || !path.include?(separator.to_s)

      path.split(separator.to_s).reduce(row) do |current, segment|
        break nil if current.nil?

        if current.is_a?(Hash) || current.is_a?(EntityEntry)
          fetch_row_value(current, segment)
        elsif current.respond_to?(:public_send)
          current.public_send(segment)
        end
      end
    end

    def normalize_columns(columns)
      Array(columns).filter_map do |column|
        next unless column.is_a?(Hash)

        key = column["key"] || column[:key]
        value = column["value"] || column[:value]
        next if key.nil?

        { key: key.to_s, value: value.to_s }
      end
    end

    def fetch_row_value(row, field)
      return nil if field.nil? || field.to_s.empty?
      if row.is_a?(EntityEntry)
        return row.file_blobs(field).map { |blob| blob.filename.to_s }.join(", ") if row.file_slug?(field)

        return row.flowchart_value(field)
      end

      return row[field] if row.respond_to?(:key?) && row.key?(field)
      return row[field.to_sym] if row.respond_to?(:key?) && row.key?(field.to_sym)
      return row[field.to_s] if row.respond_to?(:key?) && row.key?(field.to_s)

      nil
    end

    def normalize_rows(data)
      case data
      when EntityEntry then [data.to_liquid]
      when Hash then [data]
      else
        Array(data).map { |row| row.is_a?(EntityEntry) ? row.to_liquid : row }
      end
    end

    def txt_line(row)
      row.is_a?(Hash) ? row.values.map(&:to_s).join("\t") : row.to_s
    end

    def localize_columns(columns, locale)
      columns.map { |column| column.merge(header: localize_header(column[:header], locale)) }
    end

    def localize_xlsx_columns(columns, locale)
      columns.map { |column| column.merge(key: localize_header(column[:key], locale)) }
    end

    def localize_header(header, locale)
      key = header.to_s
      return key if key.empty? || !key.include?(".")

      I18n.with_locale(locale.presence || I18n.locale) do
        I18n.exists?(key) ? I18n.t(key) : key
      end
    end

    def format_cell(value, locale)
      zone_locale = locale.presence || I18n.locale
      case value
      when Time, DateTime, ActiveSupport::TimeWithZone
        I18n.l(value, locale: zone_locale)
      when Date
        I18n.l(value, locale: zone_locale)
      when Array
        value.map(&:to_s).join(", ")
      else
        value
      end
    rescue I18n::MissingTranslationData
      value.to_s
    end

    def apply_auto_filter!(sheet)
      last_row = sheet.rows.size
      last_col = sheet.rows.first&.cells&.size.to_i
      return if last_col.zero?

      sheet.auto_filter = "A1:#{Axlsx.cell_r(last_col - 1, last_row - 1)}"
    end

    def validate_worksheet_name!(sheet_name)
      name = sheet_name.to_s
      raise Error, "worksheet name is required" if name.empty?
      utf16_length = name.encode(Encoding::UTF_16LE).bytesize / 2
      if utf16_length > MAX_WORKSHEET_NAME_LENGTH || name.match?(INVALID_WORKSHEET_NAME)
        raise Error, "invalid worksheet name"
      end
    rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError => e
      raise Error, "invalid worksheet name: #{e.message}"
    end
  end
end
