# frozen_string_literal: true

module Member
  module Sources
    # Tiny duck-type that quacks like Member::Surface for link descriptors:
    # the bespoke Home / Profile / Security entries and launched member page
    # entries from Member::Sources::Pages. These are routed to dedicated
    # controllers (profiles#show, securities#show, pages#show, etc.) and never
    # flow through SurfacesController. Empty index/detail keep the settings
    # show page from raising when it reads the same presenter as editable
    # surfaces.
    BuiltinSurface = Struct.new(:key, :label, :icon, :path_seg, :default_position, :default_enabled,
                                keyword_init: true) do
      def default_position_or_default ; default_position.to_i ; end
      def default_enabled?            ; default_enabled != false ; end
      def enabled_for?(_user)         ; true ; end

      def index
        Member::Surface::Index.new(
          title: label, subtitle: nil, columns: [], empty_state: {}, per_page: nil
        )
      end

      def detail
        Member::Surface::Detail.new(
          title: label, subtitle: nil, meta: nil, sections: []
        )
      end

      # Validation no-op so EffectiveSurface and the kit treat it like a
      # real Surface for the few accessors they do touch (label/icon/key).
      def validate! ; true ; end
    end
  end
end
