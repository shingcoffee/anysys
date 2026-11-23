# frozen_string_literal: true

require "erb"
require "rouge"

# Rouge tokens wrapped in Tailwind color classes. Kramdown's highlighter
# registry outlives Rails reloads, so each render registers the current formatter.
module DeveloperDocs
  class Highlighter
    TOKEN_CLASS = {
      "Comment" => "text-slate-500 italic",
      "Keyword" => "text-violet-300",
      "String" => "text-emerald-300",
      "Number" => "text-amber-300",
      "Literal" => "text-emerald-300",
      "Name.Function" => "text-sky-300",
      "Name.Class" => "text-sky-200",
      "Name.Constant" => "text-sky-200",
      "Operator" => "text-slate-300",
      "Punctuation" => "text-slate-400",
      "Generic" => "text-slate-200"
    }.freeze

    PRE_CLASS = "overflow-x-auto rounded-lg bg-slate-950 p-4 leading-relaxed text-slate-100"

    class Formatter
      def self.call(_converter, text, lang, type, _call_opts)
        code = ::DeveloperDocs::Highlighter.highlight(text, lang)
        return code if type == :span

        %(<pre class="#{::DeveloperDocs::Highlighter::PRE_CLASS}"><code>#{code}</code></pre>)
      end
    end

    def self.install!
      # Replace callbacks retained by the gem registry from before a Rails reload.
      Kramdown::Converter.add_syntax_highlighter(:tailwind_rouge, Formatter)
    end

    def self.highlight(text, lang)
      source = text.to_s
      lexer = Rouge::Lexer.find_fancy(lang.to_s, source) || Rouge::Lexers::PlainText
      lexer.lex(source).map { |token, value| span(token, value) }.join
    end

    def self.span(token, value)
      escaped = ERB::Util.html_escape(value)
      return escaped if escaped.empty?

      name = token.respond_to?(:qualname) ? token.qualname.to_s : ""
      css = TOKEN_CLASS[name] || TOKEN_CLASS[name.split(".").first]
      return escaped if css.nil?

      %(<span class="#{css}">#{escaped}</span>)
    end
  end
end
