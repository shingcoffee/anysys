# frozen_string_literal: true

# Builds audience surface paths from ActionResolver-owned Page records only.
# Used by the public page GET/POST flow and the public action router.
module PageAudienceRouting
  private

  def sanitized_action_prefill
    raw = params[:prefill]
    return {} unless raw.respond_to?(:to_unsafe_h) || raw.respond_to?(:to_h)

    hash = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    hash.each_with_object({}) do |(key, value), kept|
      break kept if kept.size >= Pages::ActionLink::MAX_PREFILL_KEYS
      next if value.is_a?(Hash) || value.is_a?(Array)

      slug = key.to_s
      next unless slug.match?(Pages::FormParams::SLUG)

      text = value.to_s
      next if text.length > Pages::ActionLink::MAX_PREFILL_VALUE

      kept[slug] = text
    end
  end

  def audience_surface_path(page, audience: page_runtime_audience, prefill: {})
    path = case audience.to_s
    when EntityAttributeAudience::MEMBER
      member_page_path(customer_id: current_customer_id, id: page.id)
    when EntityAttributeAudience::ADMIN
      admin_audience_surface_path(page)
    else
      PageShortcuts::PublicPath.public_page(
        page: page, customer_id: current_customer_id, host: request.host
      )
    end
    raise ActiveRecord::RecordNotFound if path.blank?

    path_with_prefill(path, prefill)
  end

  # A page opened with a run token (none for a plain start). An admin opens
  # the exact page on the entity's Create Entry surface (`page`), the only way
  # into a bridge entity's page.
  def run_surface_path(page, token, audience: page_runtime_audience)
    if audience == EntityAttributeAudience::ADMIN && page.entity&.active?
      Pages::RunLink.append(new_admin_entity_entry_path(current_customer_id, page.entity), token, page: page)
    else
      Pages::RunLink.append(audience_surface_path(page, audience: audience), token)
    end
  end

  # The page a run opens on +step+. An update step's page edits +entry_id+
  # (the record its source step holds): an admin's on the entity's Edit Entry
  # surface with the exact page, a member's on the member page naming the
  # record as `entry`. Nil when the audience has nowhere to edit it.
  def run_step_surface_path(step, page, token, entry_id: nil, audience: page_runtime_audience)
    return run_surface_path(page, token, audience: audience) unless step.update?
    return if entry_id.blank?

    case audience
    when EntityAttributeAudience::ADMIN
      edit = edit_admin_entity_entry_path(current_customer_id, page.entity, entry_id) if page.entity&.active?
      Pages::RunLink.append(edit, token, page: page) if edit
    when EntityAttributeAudience::MEMBER
      Pages::RunLink.append(member_page_path(customer_id: current_customer_id, id: page.id, entry: entry_id), token)
    end
  end

  # Admins fill records from the entity's Create Entry surface. Unbound or
  # inactive bindings have no entry form, so they land on the form's catalog tab.
  def admin_audience_surface_path(page)
    entity = page.entity
    if entity && !entity.category_bridge? && entity.active?
      new_admin_entity_entry_path(current_customer_id, entity)
    else
      Admin::Pages::BrowsePath.for(page, customer_id: current_customer_id)
    end
  end

  def path_with_prefill(path, prefill)
    return path if prefill.blank?

    "#{path}?#{ { prefill: prefill }.to_query }"
  end
end
