# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module CodeGenerators
        class SourcePreviewsController < ApplicationController
          dashboard_menu_item :maintenance

          def create
            assembler = ::CodeGenerators::SourceAssembler.new(generator_params)
            source = assembler.assemble
            highlighted = highlight_ruby(source)
            render json: { source: source, highlighted: highlighted, line_count: source.lines.count }
          end

          private

          def generator_params
            params.permit(:kind, :file_name, :category, :description, :version,
                          :registered_names, :methods_body)
          end

          def highlight_ruby(source)
            lexer = Rouge::Lexers::Ruby.new
            formatter = Rouge::Formatters::HTML.new
            formatter.format(lexer.lex(source)).html_safe
          end
        end
      end
    end
  end
end
