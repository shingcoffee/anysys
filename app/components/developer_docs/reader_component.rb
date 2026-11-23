# frozen_string_literal: true

module DeveloperDocs
  # Three-region reader: page list, article, and same-page heading links.
  # The left rail is a full-height sticky sidebar on desktop and a slide-over
  # drawer on mobile, opened from a sticky "Contents" bar. The right rail shows
  # the same-page headings (with scroll-spy) when the reader has room and is
  # not a hub home.
  class ReaderComponent < ApplicationComponent
    include DeveloperDocs::NavigationHelper

    renders_one :header

    ARTICLE_GRID = "min-w-0 [@media(min-height:640px)]:@min-[52rem]/docs:grid [@media(min-height:640px)]:@min-[52rem]/docs:grid-cols-[16rem_minmax(0,1fr)] [@media(min-height:640px)]:@min-[52rem]/docs:gap-10"
    # The right page TOC only claims a column once the article keeps a full
    # reading measure beside it; narrower readers use the inline disclosure.
    TOC_GRID = "#{ARTICLE_GRID} [@media(min-height:640px)]:@min-[76rem]/docs:grid-cols-[16rem_minmax(0,1fr)_12rem]"

    # Shared by article pages and the hub's overview prose.
    READING_MEASURE = "max-w-[52rem]"

    # One card holds the rail, article and page TOC, like every other admin
    # surface. Horizontal padding lives on the card, never on the article, so
    # the article keeps its exact reading measure. Once the rail shows, it
    # runs flush to the card's left edge as a tinted column.
    PANEL_CLASSES = "rounded-xl border border-border-subtle bg-surface shadow-xs px-4 py-6 " \
      "@min-[36rem]/docs:px-8 @min-[36rem]/docs:py-8 " \
      "[@media(min-height:640px)]:@min-[52rem]/docs:py-0 [@media(min-height:640px)]:@min-[52rem]/docs:pl-0 [@media(min-height:640px)]:@min-[52rem]/docs:pr-8"
    RAIL_CLASSES = "hidden min-w-0 [@media(min-height:640px)]:@min-[52rem]/docs:block " \
      "[@media(min-height:640px)]:@min-[52rem]/docs:rounded-l-xl [@media(min-height:640px)]:@min-[52rem]/docs:border-r " \
      "[@media(min-height:640px)]:@min-[52rem]/docs:border-border-subtle [@media(min-height:640px)]:@min-[52rem]/docs:bg-canvas-elevated " \
      "[@media(min-height:640px)]:@min-[52rem]/docs:px-3 [@media(min-height:640px)]:@min-[52rem]/docs:py-6"

    # Leave the slotted AdminPageComponent on its own type: text-subtitle titles
    # and text-body-sm summaries. Breadcrumbs stay on their text-sm rule.
    HEADER_CLASSES = "min-w-0 [&_div]:min-w-0 [&>div]:mb-0 " \
      "[&_nav]:mb-4 [&_nav]:max-w-full [&_nav]:flex-wrap [&_nav]:gap-y-1 [&_nav]:text-text-secondary " \
      "[&_nav_a]:focus-visible:outline-none [&_nav_a]:focus-visible:ring-2 [&_nav_a]:focus-visible:ring-accent " \
      "[&_p]:mt-3 [&_p]:text-text-secondary [&_p]:[overflow-wrap:anywhere]"

    # App type tokens, not a separate reading scale. Descendant selectors
    # outrank global paragraph defaults and renderer-owned utilities without
    # changing sanitized HTML, heading IDs, or syntax colors. Code keeps the
    # application mono family and the base 0.9em / pre sizes.
    PROSE_CLASSES = "w-full min-w-0 font-sans text-base leading-normal tracking-[-0.011em] text-text-secondary [overflow-wrap:anywhere] " \
      "[&_p]:my-4 [&_p]:text-base [&_p]:leading-normal " \
      "[&_li]:text-base [&_li]:leading-normal [&_li]:marker:text-text-tertiary " \
      "[&_h2]:mt-12 [&_h2]:mb-3 [&_h2]:scroll-mt-28 [&_h2]:text-2xl [&_h2]:leading-tight [&_h2]:font-semibold [&_h2]:text-text-primary [&>h2:first-child]:mt-0 " \
      "[&_h3]:mt-8 [&_h3]:mb-2 [&_h3]:scroll-mt-28 [&_h3]:text-xl [&_h3]:leading-snug [&_h3]:font-semibold [&_h3]:text-text-primary " \
      "[&_h4]:mt-6 [&_h4]:mb-2 [&_h4]:scroll-mt-28 [&_h4]:text-lg [&_h4]:leading-snug [&_h4]:font-semibold [&_h4]:text-text-primary " \
      "[&_ul]:my-4 [&_ul]:list-disc [&_ul]:pl-6 [&_ol]:my-4 [&_ol]:list-decimal [&_ol]:pl-6 " \
      "[&_li_ul]:my-2 [&_li_ol]:my-2 [&_li_li+li]:mt-2 " \
      "[&_a]:font-medium [&_a]:text-accent-text [&_a]:underline [&_a]:decoration-accent-muted [&_a]:underline-offset-2 [&_a:hover]:decoration-accent-text " \
      "[&_a]:focus-visible:outline-none [&_a]:focus-visible:ring-2 [&_a]:focus-visible:ring-accent [&_a]:focus-visible:ring-offset-2 " \
      "[&_:is(h2,h3,h4)>a]:text-sm [&_:is(h2,h3,h4)>a]:leading-normal [&_:is(h2,h3,h4)>a]:font-normal [&_:is(h2,h3,h4)>a]:text-text-tertiary [&_:is(h2,h3,h4)>a]:no-underline " \
      "[&_strong]:font-semibold [&_strong]:text-text-primary " \
      "[&_table]:my-6 [&_table]:block [&_table]:w-full [&_table]:max-w-full [&_table]:overflow-x-auto [&_table]:border-collapse [&_table]:rounded-xl [&_table]:border [&_table]:border-border-subtle [&_table]:bg-surface [&_table]:text-base [&_table]:leading-normal " \
      "[&_thead]:bg-canvas-elevated [&_th]:border-b [&_th]:border-border-subtle [&_th]:px-4 [&_th]:py-2.5 [&_th]:align-top [&_th]:text-left [&_th]:font-semibold [&_th]:text-text-primary " \
      "[&_td]:border-b [&_td]:border-border-subtle [&_td]:px-4 [&_td]:py-2.5 [&_td]:align-top [&_tbody_tr:last-child_td]:border-b-0 " \
      "[&_blockquote]:my-6 [&_blockquote]:border-l-[3px] [&_blockquote]:border-border-strong [&_blockquote]:pl-4 [&_blockquote]:text-text-secondary " \
      "[&_:not(pre)>code]:rounded-md [&_:not(pre)>code]:border [&_:not(pre)>code]:border-border-subtle [&_:not(pre)>code]:bg-surface [&_:not(pre)>code]:px-1.5 [&_:not(pre)>code]:py-0.5 [&_:not(pre)>code]:font-mono [&_:not(pre)>code]:text-text-primary " \
      "[&_pre]:my-6 [&_pre]:max-w-full [&_pre]:overflow-x-auto [&_pre]:whitespace-pre [&_pre]:[overflow-wrap:normal] [&_pre]:break-normal [&_pre]:rounded-xl [&_pre]:border [&_pre]:border-slate-800 [&_pre]:bg-slate-950 [&_pre]:p-4 [&_pre]:font-mono [&_pre]:text-sm [&_pre]:leading-relaxed [&_pre]:text-slate-100 " \
      "[&_pre_code]:bg-transparent [&_pre_code]:p-0 [&_pre_code]:font-mono [&_pre_code]:text-inherit " \
      "[&_aside]:text-base [&_aside]:leading-normal [&_aside>p:first-child]:mt-0 [&_aside>p:first-child]:mb-2 [&_aside>p:first-child]:text-sm [&_aside>p:first-child]:leading-normal [&_aside>p:first-child]:font-semibold [&_aside>p:first-child]:normal-case [&_aside>p:first-child]:tracking-normal [&_aside>:last-child]:mb-0 " \
      "[&_hr]:my-10 [&_hr]:border-border-subtle " \
      "[&_figure]:my-8 [&_figure]:min-w-0 [&_figure>a]:block [&_figure>a]:overflow-hidden [&_figure>a]:rounded-xl [&_figure>a]:border [&_figure>a]:border-border-subtle [&_figure>a]:bg-canvas-elevated [&_figure>a]:shadow-xs " \
      "[&_figure_img]:block [&_figure_img]:h-auto [&_figure_img]:w-full [&_figure_img]:max-w-full " \
      "[&_figcaption]:mt-3 [&_figcaption]:flex [&_figcaption]:min-w-0 [&_figcaption]:flex-col [&_figcaption]:gap-2 [&_figcaption]:text-sm [&_figcaption]:leading-normal [&_figcaption]:text-text-secondary " \
      "@min-[40rem]/docs:[&_figcaption]:flex-row @min-[40rem]/docs:[&_figcaption]:items-start @min-[40rem]/docs:[&_figcaption]:justify-between " \
      "[&_figcaption>span]:min-w-0 [&_figcaption>span]:[overflow-wrap:anywhere] [&_figcaption_p]:my-0 [&_figcaption_p]:text-sm [&_figcaption_p]:leading-normal " \
      "[&_figcaption>a]:inline-flex [&_figcaption>a]:min-h-11 [&_figcaption>a]:min-w-0 [&_figcaption>a]:items-center [&_figcaption>a]:self-start [&_figcaption>a]:font-normal"

    FOCUS_RING = "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"

    attr_reader :page, :translation_scope, :locale, :article_variant, :home_groups, :home_path

    def initialize(page:, translation_scope: "developer_docs", locale: nil, article_variant: :reference,
                   home_groups: nil, home_path: nil)
      @page = page
      @translation_scope = translation_scope
      @locale = locale
      @article_variant = article_variant
      @home_groups = home_groups
      @home_path = home_path
    end

    def reader_text(key, **options)
      t("#{translation_scope}.#{key}", **options)
    end

    def current_group
      page.current_group
    end

    def section_entries
      return [] if current_group.blank?

      current_group.entries.reject(&:active)
    end

    def home?
      !home_groups.nil?
    end

    def show_page_toc?
      !home? && page.headings.any?
    end

    def reader_grid_class
      "#{show_page_toc? ? TOC_GRID : ARTICLE_GRID} #{PANEL_CLASSES}"
    end

    def rail_class
      RAIL_CLASSES
    end

    # Hubs give the topic grid the full column; prose always stays on the
    # reading measure, centered between the rails.
    def center_class
      measure = home? ? nil : READING_MEASURE
      [measure, "[@media(min-height:640px)]:@min-[52rem]/docs:py-10"].compact.join(" ")
    end

    def article_class
      variant_classes = if article_variant == :customer
        "customer-doc [&_li+li]:mt-3"
      else
        "developer-doc [&_li+li]:mt-2 [&_blockquote]:italic"
      end
      measure = home? ? READING_MEASURE : nil
      [variant_classes, PROSE_CLASSES, measure].compact.join(" ")
    end

    def header_class
      HEADER_CLASSES
    end

    def id_prefix
      translation_scope.delete_suffix("_docs")
    end

    def article_id
      "#{id_prefix}-doc-article"
    end

    def doc_set_title
      reader_text("breadcrumb.reference")
    end

    def toc_link_class(level)
      nested = level.to_i >= 3
      inset = nested ? "pl-6 text-text-tertiary" : "pl-3 text-text-secondary"
      "-ml-px block min-w-0 border-l-2 border-transparent py-1.5 pr-1 text-sm leading-5 [overflow-wrap:anywhere] transition-colors " \
        "hover:border-border-strong hover:text-text-primary aria-[current=location]:border-accent aria-[current=location]:font-medium " \
        "aria-[current=location]:text-accent-text #{FOCUS_RING} #{inset}"
    end

    def search_submit_class
      "inline-flex min-h-11 min-w-0 shrink-0 items-center justify-center gap-2 rounded-lg border border-border-subtle bg-surface px-3 py-2 text-sm font-medium text-text-primary [overflow-wrap:anywhere] transition-colors hover:bg-surface-hover #{FOCUS_RING} focus-visible:ring-offset-2"
    end

    def clear_link_class(surface)
      height = surface == :mobile ? "min-h-11" : "min-h-8"
      "inline-flex #{height} min-w-0 items-center justify-center rounded-md px-2 text-sm font-medium text-text-secondary underline decoration-border-strong underline-offset-4 [overflow-wrap:anywhere] transition-colors hover:text-text-primary #{FOCUS_RING}"
    end

    def search_field_id(surface = :desktop)
      surface == :mobile ? "developer-docs-q-mobile" : "developer-docs-q"
    end

    def navigation_label(slug, title:)
      docs_navigation_label(slug, title: title, translation_scope: translation_scope)
    end

    def current_entry
      current_group&.entries&.find(&:active)
    end

    def current_path
      current_entry&.path || page.search_path
    end

    def context_title_id(surface)
      "#{id_prefix}-doc-context-#{surface}-#{page.slug}-title"
    end

    def context_label_id(surface)
      "#{id_prefix}-doc-context-#{surface}-label"
    end

    def group_path
      return unless home_path.present? && current_group

      "#{home_path}##{id_prefix}-doc-guide-group-#{current_group.key}"
    end

    def sequence_pages
      [[:previous, page.previous_page], [:next, page.next_page]].reject { |_, link| link.nil? }
    end

    def sequence_link_class(direction)
      alignment = direction == :next ? "items-end text-right @min-[30rem]/hub:col-start-2" : "items-start"
      "group flex min-w-0 flex-col gap-1 rounded-xl border border-border-subtle bg-surface px-4 py-3.5 [overflow-wrap:anywhere] transition hover:border-accent-muted hover:shadow-sm #{FOCUS_RING} focus-visible:ring-offset-2 #{alignment}"
    end
  end
end
