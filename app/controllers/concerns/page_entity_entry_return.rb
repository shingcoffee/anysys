# frozen_string_literal: true

# Brings an admin who submitted a page from its entity's entries area
# (Admin::EntityEntriesController#new / #edit, or the "+ Add New" dialog
# frame; the submit URL carries PageRendering::ENTITY_ENTRY_RETURN) back
# there: once saved, to the created entry or the entity's entries, else to
# the entry form. +entry_id+ names the edited entry; +label_field+ rides
# along so the dialog can label the entry it hands back to its dropdown.
module PageEntityEntryReturn
  extend ActiveSupport::Concern

  ENTRY_ID = /\A[1-9]\d*\z/

  private

  def entity_entry_return?(page = @page)
    params[:return_to] == PageRendering::ENTITY_ENTRY_RETURN && page == @page && page.entity.present? &&
      page_runtime_audience == EntityAttributeAudience::ADMIN
  end

  def edited_entity_entry_id
    params[:entry_id] if params[:entry_id].is_a?(String) && params[:entry_id].match?(ENTRY_ID)
  end

  def entity_entry_form_path
    if edited_entity_entry_id
      edit_admin_entity_entry_path(current_customer_id, @page.entity, edited_entity_entry_id)
    else
      new_admin_entity_entry_path(current_customer_id, @page.entity, label_field: entity_entry_label_field)
    end
  end

  # { path:, notice:, flash: } once the submission saved +entry+ on this
  # return, else nil.
  def entity_entry_landing(entry)
    return unless entity_entry_return? && entry && entry.entity_id == @page.entity.id

    if edited_entity_entry_id
      { path: edited_entry_landing_path(entry), notice: t("admin_misc.entities.entry_form.updated"), flash: {} }
    else
      { path: admin_entity_entry_path(current_customer_id, @page.entity, entry, label_field: entity_entry_label_field),
        notice: t("admin_misc.entities.entry_form.created"), flash: { reveal_section: first_association_reveal }.compact }
    end
  end

  # A link row has no entries list of its own: it was edited from a record
  # page's dialog, which watches its frame for the saved row.
  def edited_entry_landing_path(entry)
    return admin_entity_entry_path(current_customer_id, @page.entity, entry) if @page.entity.category_bridge?

    admin_entity_path(current_customer_id, @page.entity)
  end

  # Turbo drops a redirect's #fragment, so the created entry's first
  # association section to bring into view travels in the flash instead.
  def first_association_reveal
    association = ::Entities::EntryAssociations.new(entity: @page.entity, customer: current_customer).all.first
    { id: Admin::Entities::AssociationSectionComponent.section_id(association) } if association
  end

  def entity_entry_label_field
    params[:label_field] if params[:label_field].is_a?(String)
  end
end
