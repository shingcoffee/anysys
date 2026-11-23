# frozen_string_literal: true

module FormFields
  class FileUploadFieldComponent < BaseFieldComponent
    attr_reader :accept, :multiple, :max_size

    def initialize(accept: nil, multiple: false, max_size: nil, **args)
      super(**args)
      @accept = accept
      @multiple = multiple
      @max_size = max_size
    end

    # Filenames an edited record already holds; an empty input keeps them.
    def current_files
      Array(value).grep(String).compact_blank
    end

    def input_required?
      required && current_files.empty?
    end

    def max_size_label
      return nil unless max_size

      if max_size >= 1_000_000
        "#{max_size / 1_000_000}MB"
      else
        "#{max_size / 1_000}KB"
      end
    end

    def dropzone_classes
      "relative border-2 border-dashed border-gray-300 rounded-lg p-6 sm:p-8 text-center " \
        "hover:border-gray-400 hover:shadow-md " \
        "focus-within:border-gray-400 " \
        "transition-all duration-200 cursor-pointer group"
    end

    def dropzone_icon_classes
      "mx-auto h-12 w-12 text-gray-300 group-hover:text-gray-400 transition-colors duration-150"
    end

    def upload_cta_classes
      palette = color_palette(theme)
      "text-sm font-medium #{palette[:text]}"
    end

    private

    def field_type
      :file
    end
  end
end
