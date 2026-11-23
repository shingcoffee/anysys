# frozen_string_literal: true

module AiAssistant
  module Assistant
    module Prompt
      module Sections
        # The website section catalogue, rendered from {Websites::SectionKit}
        # and {Websites::SectionFields}.
        #
        # Only the one-line purposes are prose (the `### Purposes` list in
        # website_section_kit.md); every type, group, prop, kind, option and
        # list bound comes from the registries, so adding a section type or a
        # prop reaches the prompt with no edit here.
        class WebsiteSectionKit < Section
          heads "Website section kit (authoritative, generated from the live registries)"
          document "website_section_kit"

          PURPOSES_HEADING = /^### Purposes\n/
          PURPOSE_LINE = /^- `([a-z_]+)` — (.+)$/

          class << self
            # @return [Hash{String => String}] section type → one-line purpose
            def purposes
              _intro, list = Document.read(document_name).split(PURPOSES_HEADING, 2)
              list.to_s.scan(PURPOSE_LINE).to_h
            end
          end

          private

          def body
            return nil unless context.website_enabled?

            [intro, table].join("\n\n")
          end

          def intro
            document.split(PURPOSES_HEADING, 2).first.strip
          end

          def table
            purposes = self.class.purposes
            rows = Websites::SectionKit.groups.flat_map do |group, types|
              types.map do |type|
                "| `#{type}` | #{group} | #{purposes.fetch(type, "—")} | #{props(Websites::SectionFields.full_schema_for(type))} |"
              end
            end
            ["| type | group | purpose | props |", "| --- | --- | --- | --- |", *rows].join("\n")
          end

          def props(fields)
            return "—" if fields.empty?

            fields.map { |field| "`#{field[:key]}` #{kind(field)}" }.join("; ")
          end

          def kind(field)
            case field[:kind]
            when :textarea then "long text"
            when :select then "choice(#{field[:options].map { |option| "`#{option}`" }.join("/")})"
            when :array
              items = field[:item_fields].map { |item| "`#{item[:key]}` #{kind(item)}" }.join(", ")
              "list[#{field[:min]}–#{field[:max]}] of {#{items}}"
            else string_kind(field[:key])
            end
          end

          def string_kind(key)
            return "**image**" if Websites::SectionKit::IMAGE_KEYS.include?(key)
            return "**link**" if Websites::SectionKit::HREF_KEYS.include?(key)

            "text"
          end
        end
      end
    end
  end
end
