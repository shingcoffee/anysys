# frozen_string_literal: true

class CodeBlockComponent < ApplicationComponent
  attr_reader :code, :language, :filename

  def initialize(code:, language: "ruby", filename: nil)
    @code = code
    @language = language
    @filename = filename || default_filename
  end

  def render?
    code.present?
  end

  def line_count
    code.lines.count
  end

  def highlighted_code
    return "" if code.blank?

    lexer = Rouge::Lexers::Ruby.new
    formatter = Rouge::Formatters::HTML.new
    formatter.format(lexer.lex(code)).html_safe
  end

  def highlight_line(line)
    return "" if line.blank?

    lexer = Rouge::Lexers::Ruby.new
    formatter = Rouge::Formatters::HTML.new
    formatter.format(lexer.lex(line.chomp)).html_safe
  end

  private

  def default_filename
    case language.to_s.downcase
    when "ruby" then "contract.rb"
    when "javascript", "js" then "script.js"
    when "python", "py" then "script.py"
    else "code.#{language}"
    end
  end
end
