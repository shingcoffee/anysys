# frozen_string_literal: true

MenuItem = Struct.new(
  :key, :label_key, :description_key, :path_proc, :permitted_by, :sidebar_contributor,
  :feature_module_key, :children, :active_paths,
  keyword_init: true
) do
  # Translated at call time (not load time) so the label follows the
  # request locale — the constant only ever stores the stable I18n key.
  def label
    I18n.t(label_key)
  end

  def description
    I18n.t(description_key) if description_key
  end

  def path_for(customer)
    path_proc&.call(customer)
  end

  def dropdown?
    children.present?
  end

  def active_for?(customer, path)
    Array(active_paths).any? do |prefix_proc|
      prefix = prefix_proc.call(customer)
      path == prefix || path.start_with?("#{prefix}/")
    end
  end

  def active_child_for(customer, path)
    # Later destinations override broader prefixes when dropdown items overlap.
    children.to_a.reverse.find { |child| child.active_for?(customer, path) }
  end

  def permitted_for?(user)
    case permitted_by
    when nil    then true
    when Proc   then permitted_by.call(user)
    when Symbol then user.respond_to?(permitted_by) && user.public_send(permitted_by)
    else false
    end
  end
end
