# frozen_string_literal: true

require "prawn"
require "stringio"

module FlowchartRuntime
  # Renders a title / body / optional table PDF through Prawn and stores the
  # bytes as an ActiveStorage blob. Generated send steps never rescue gem errors.
  module Document
    class Error < StandardError; end

    PRAWN_ERRORS = Prawn::Errors.constants.filter_map do |name|
      error_class = Prawn::Errors.const_get(name)
      error_class if error_class.is_a?(Class) && error_class < StandardError
    end.freeze

    PAGE_SIZES = {
      "a4" => "A4",
      "letter" => "LETTER",
      "legal" => "LEGAL"
    }.freeze
    ORIENTATIONS = {
      "portrait" => :portrait,
      "landscape" => :landscape
    }.freeze

    BUNDLED_FONT_PATHS = [
      Rails.root.join("vendor/fonts/DroidSansFallbackFull.ttf"),
      Rails.root.join("app/assets/fonts/DroidSansFallbackFull.ttf")
    ].map(&:to_s).freeze
    SYSTEM_FONT_PATH = "/usr/share/fonts/google-droid-sans-fonts/DroidSansFallbackFull.ttf"
    CJK_CHAR = /[\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}]/
    HEADING = /\A##\s+/

    module_function

    def pdf(title:, body:, filename: "document.pdf", rows: nil, columns: [],
            customer_id: nil, page_size: "a4", orientation: "portrait",
            header: nil, footer: nil, page_numbers: false)
      payload = build_pdf(
        title: title, body: body, rows: rows, columns: columns,
        page_size: page_size, orientation: orientation,
        header: header, footer: footer, page_numbers: page_numbers
      )
      blob = store_blob(payload, filename: filename, customer_id: customer_id)
      {
        "blob_id" => blob.id,
        "signed_id" => blob.signed_id,
        "filename" => blob.filename.to_s,
        "content_type" => blob.content_type.presence || "application/pdf",
        "byte_size" => blob.byte_size,
        "checksum" => blob.checksum,
        "customer_id" => customer_id
      }.compact
    rescue *PRAWN_ERRORS, ActiveStorage::IntegrityError, ActiveStorage::FileNotFoundError,
           ActiveRecord::ActiveRecordError => error
      raise Error, error.message
    end

    def cjk_font_path
      BUNDLED_FONT_PATHS.find { |path| File.file?(path) } ||
        (File.file?(SYSTEM_FONT_PATH) ? SYSTEM_FONT_PATH : nil)
    end

    def build_pdf(title:, body:, rows:, columns:, page_size:, orientation:, header:, footer:, page_numbers:)
      headers = normalize_columns(columns)
      collection = Array(rows)
      font_path = cjk_font_path if contains_cjk?(title, body, collection, headers, header, footer)
      size = PAGE_SIZES[page_size.to_s] || PAGE_SIZES["a4"]
      layout = ORIENTATIONS[orientation.to_s] || :portrait
      has_header = header.to_s.present?
      has_footer = footer.to_s.present? || page_numbers
      Prawn::Document.new(
        page_size: size,
        page_layout: layout,
        compress: false,
        top_margin: has_header ? 56 : 36,
        bottom_margin: has_footer ? 56 : 36
      ) do |doc|
        apply_font!(doc, font_path)
        write_chrome(doc, header: header, footer: footer, font_path: font_path)
        write_line(doc, title, font_path: font_path, size: 18, style: :bold)
        doc.move_down 12
        write_body(doc, body, font_path: font_path)
        write_table(doc, collection, headers, font_path: font_path)
        if page_numbers
          doc.number_pages(
            "<page> / <total>",
            at: [doc.bounds.right - 80, doc.bounds.bottom - 24],
            width: 80,
            align: :right,
            size: 9
          )
        end
      end.render
    end

    def contains_cjk?(title, body, rows, headers, header = nil, footer = nil)
      pieces = [title, body, header, footer]
      pieces.concat(headers.map { |column| column[:header] })
      rows.each do |row|
        if headers.any?
          pieces.concat(headers.map { |column| fetch_row_value(row, column[:field]).to_s })
        else
          pieces << (row.is_a?(Hash) ? row.values.map(&:to_s).join : row.to_s)
        end
      end
      pieces.any? { |piece| piece.to_s.match?(CJK_CHAR) }
    end

    def apply_font!(doc, font_path)
      return if font_path.nil?

      doc.font_families.update("CJK" => { normal: font_path, bold: font_path })
      doc.font "CJK"
    end

    def write_chrome(doc, header:, footer:, font_path:)
      header_text = header.to_s
      footer_text = footer.to_s
      return if header_text.empty? && footer_text.empty?

      doc.repeat(:all) do
        unless header_text.empty?
          doc.draw_text printable(header_text, font_path), at: [doc.bounds.left, doc.bounds.top + 20], size: 9
        end
        unless footer_text.empty?
          doc.draw_text printable(footer_text, font_path), at: [doc.bounds.left, doc.bounds.bottom - 20], size: 9
        end
      end
    end

    def write_body(doc, body, font_path:)
      body.to_s.each_line do |raw|
        line = raw.chomp
        if line.match?(HEADING)
          doc.move_down 8
          write_line(doc, line.sub(HEADING, ""), font_path: font_path, size: 14, style: :bold)
        elsif line.strip.empty?
          doc.move_down 8
        else
          write_line(doc, line, font_path: font_path, size: 11)
        end
      end
    end

    def write_table(doc, collection, headers, font_path:)
      return if collection.empty? && headers.empty?

      doc.move_down 16
      if headers.any?
        write_line(doc, headers.map { |column| column[:header] }.join(" | "), font_path: font_path, size: 11, style: :bold)
        collection.each do |row|
          write_line(doc, headers.map { |column| fetch_row_value(row, column[:field]).to_s }.join(" | "), font_path: font_path, size: 11)
        end
      else
        collection.each do |row|
          write_line(doc, row.is_a?(Hash) ? row.values.map(&:to_s).join(" | ") : row.to_s, font_path: font_path, size: 11)
        end
      end
    end

    def write_line(doc, text, font_path:, size:, style: :normal)
      doc.text printable(text, font_path), size: size, style: font_path ? :normal : style
    end

    def printable(text, font_path)
      source = text.to_s
      return source if font_path

      source.gsub(CJK_CHAR, "?")
    end

    def store_blob(payload, filename:, customer_id:)
      name = File.basename(filename.to_s)
      name = "document.pdf" if name.empty?
      name = "#{name}.pdf" unless name.downcase.end_with?(".pdf")
      metadata = {}
      metadata["customer_id"] = customer_id if customer_id

      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(payload),
        filename: name,
        content_type: "application/pdf",
        metadata: metadata
      )
      blob.update_column(:customer_id, customer_id) if customer_id && blob.customer_id != customer_id
      blob
    end

    def normalize_columns(columns)
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

    def fetch_row_value(row, field)
      return nil if field.nil? || field.to_s.empty?
      return row[field] if row.respond_to?(:key?) && row.key?(field)
      return row[field.to_sym] if row.respond_to?(:key?) && row.key?(field.to_sym)
      return row[field.to_s] if row.respond_to?(:key?) && row.key?(field.to_s)

      nil
    end
  end
end
