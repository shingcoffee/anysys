# frozen_string_literal: true

module AiAssistant
  module Assistant
    module Prompt
      module Sections
        # The tenant's website pages. A `page_id` from this list is the only
        # way to revise a page, and the published flag is what keeps the model
        # off pages visitors can already see. Rendered even for an empty site:
        # "there are no pages yet" is what makes the first page the home page.
        class WebsiteCatalog < Section
          heads "This workspace's website"

          LIMIT = 30
          # Characters of off-screen draft JSON carried per prompt. A revision
          # replaces a page's sections outright, so a draft the model cannot
          # see is a draft whose copy it would lose.
          DRAFT_BUDGET = 12_000

          private

          def body
            return nil unless context.website_enabled?

            pages = context.website_pages
            return "The website has no pages yet. Every page you build is new, and the first becomes the home page." if pages.empty?

            [listing(pages), focus, other_drafts(pages)].compact.join("\n\n")
          end

          def listing(pages)
            rows = pages.first(LIMIT).map { |page| row(page) }
            rows << "- …and #{pages.size - LIMIT} more pages not listed." if pages.size > LIMIT
            [
              "Pages of the tenant's website in navigation order: page_id · title · slug · status · section " \
                "types in order. A draft page may be revised with its `page_id`; a published page is read-only.",
              ("There is no home page yet: the first new page you build becomes home." if pages.none?(&:home?)),
              *rows
            ].compact.join("\n")
          end

          def row(page)
            types = section_hashes(page).filter_map { |section| section["type"].presence }
            "- #{page.id} · \"#{plain(page.title)}\" · #{page.home? ? "(home)" : plain(page.slug)} · " \
              "#{status(page)} · #{types.any? ? types.join(", ") : "(no sections)"}"
          end

          def status(page)
            page.published? ? "published (read-only)" : "draft"
          end

          def focus
            page = context.focused_website_page
            return nil unless page

            <<~TEXT.strip
              ### Page on screen: "#{plain(page.title)}" (page_id #{page.id}, #{status(page)})

              #{focus_instruction(page)} Its current sections:

              ```json
              #{json(sections(page))}
              ```
            TEXT
          end

          def focus_instruction(page)
            if page.published?
              "The admin is looking at this published page. It is read-only: to change it, build a new " \
                "draft page (no `page_id`) based on it and say so."
            else
              "The admin is looking at this page. Treat an unqualified request (\"make the headline punchier\", " \
                "\"add an FAQ\") as a revision of it: send `page_id` #{page.id} with its complete sections, " \
                "copying what you do not change verbatim."
            end
          end

          def other_drafts(pages)
            focused = context.focused_website_page
            drafts = pages.first(LIMIT).reject { |page| page.published? || page == focused }
            return nil if drafts.empty?

            shown, left_out = fit_drafts(drafts)
            [
              "### Current sections of the other draft pages",
              "Each line is a page's id and title, then its sections. Revise one with its `page_id`, copying " \
                "what you do not change verbatim.",
              *shown,
              left_out_note(left_out)
            ].compact.join("\n")
          end

          def fit_drafts(drafts)
            used = 0
            drafts.each_with_object([[], []]) do |page, (shown, left_out)|
              line = "- page_id #{page.id} \"#{plain(page.title)}\": #{json(sections(page))}"
              if used + line.size > DRAFT_BUDGET
                left_out << page
              else
                shown << line
                used += line.size
              end
            end
          end

          def left_out_note(pages)
            return nil if pages.empty?

            titles = pages.map { |page| "\"#{plain(page.title)}\"" }.join(", ")
            "Not shown for length: #{titles}. You know only their outline, so rewrite one in full only when " \
              "the admin asks for that."
          end

          def sections(page)
            section_hashes(page).map { |section| { "type" => section["type"], "props" => section["props"] || {} } }
          end

          def section_hashes(page)
            Array(page.sections).grep(Hash).map(&:stringify_keys)
          end
        end
      end
    end
  end
end
