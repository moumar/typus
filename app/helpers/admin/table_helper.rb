module Admin

  module TableHelper

    def build_table(model, fields, items, link_options = {}, association = nil)
      render "admin/helpers/table/table",
             :model => model,
             :fields => fields,
             :items => items,
             :link_options => link_options,
             :headers => table_header(model, fields)
    end

    def table_header(model, fields)
      fields.map do |key, value|

        key = key.gsub(".", " ") if key.match(/\./)
        content = model.human_attribute_name(key)

        if params[:action] == "index" && model.typus_options_for(:sortable)
          association = model.reflect_on_association(key.to_sym)
          order_by = association ? association.primary_key_name : key

          if (model.model_fields.map(&:first).map { |i| i.to_s }.include?(key) || model.reflect_on_all_associations(:belongs_to).map(&:name).include?(key.to_sym))
            sort_order = case params[:sort_order]
                         when 'asc' then ['desc', '&darr;']
                         when 'desc' then ['asc', '&uarr;']
                         else [nil, nil]
                         end
            switch = sort_order.last if params[:order_by].eql?(order_by)
            options = { :order_by => order_by, :sort_order => sort_order.first }
            message = [ content, switch ].compact
            link_to raw(message.join(" ")), params.merge(options)
          else
            content
          end

        else
          content
        end

      end
    end

    def table_fields_for_item(item, fields, link_options)
      fields.map do |key, value|
        case value
        when :boolean then table_boolean_field(key, item)
        when :datetime then table_datetime_field(key, item, link_options)
        when :date then table_datetime_field(key, item, link_options)
        when :time then table_datetime_field(key, item, link_options)
        when :belongs_to then table_belongs_to_field(key, item)
        when :tree then table_tree_field(key, item)
        when :file then table_file_field(key, item, link_options)
        when :position then table_position_field(key, item)
        when :selector then table_selector(key, item)
        when :transversal then table_transversal(key, item)
        when :has_and_belongs_to_many then table_has_and_belongs_to_many_field(key, item)
        else
          table_string_field(key, item, link_options)
        end
      end
    end

    def table_actions(model, item, connector = " / ")
      Array.new.tap do |data|
        data << table_default_action(model, item)
        data << table_action(model, item)
      end.compact.join(connector).html_safe
    end

    def table_default_action(model, item)
      default_action = item.class.typus_options_for(:default_action_on_item)
      action = if model.typus_user_id? && current_user.is_not_root?
                 item.owned_by?(current_user) ? default_action : "show"
               elsif current_user.cannot?("edit", model)
                 'show'
               else
                 default_action
               end

      options = { :controller => "/admin/#{item.class.to_resource}",
                  :action => action,
                  :id => item.id }

      link_to _t(action.capitalize), options
    end

    def table_action(model, item)
      case params[:action]
      when "index"
        action = "trash"
        options = { :action => 'destroy', :id => item.id }
        method = :delete
      when "edit", "show", "update"
        action = "unrelate"
        options = { :action => 'unrelate', :id => params[:id], :resource => model, :resource_id => item.id }
      end

      condition = true

      case params[:action]
      when 'index'
        condition = if model.typus_user_id? && current_user.is_not_root?
                      item.owned_by?(current_user)
                    elsif (current_user.id.eql?(item.id) && model.eql?(Typus.user_class))
                      false
                    else
                      current_user.can?('destroy', model)
                    end
      when 'show'
        condition = if @resource.typus_user_id? && current_user.is_not_root?
                      @item.owned_by?(current_user)
                    end
      end

      confirm = _t("#{action.titleize} %{resource}?", :resource => model.model_name.human)

      if condition
        link_to _t(action.titleize), options, :title => _t(action.titleize), :confirm => confirm, :method => method
      end
    end

    def table_belongs_to_field(attribute, item)
      if att_value = item.send(attribute)
        action = item.send(attribute).class.typus_options_for(:default_action_on_item)
        if current_user.can?(action, att_value.class.name)
          link_to att_value.to_label, :controller => "/admin/#{att_value.class.to_resource}", :action => action, :id => att_value.id
        else
          att_value.to_label
        end
      else
        "&mdash;".html_safe
      end
    end

    def table_has_and_belongs_to_many_field(attribute, item)
      item.send(attribute).map { |i| i.to_label }.join(", ")
    end

    def table_string_field(attribute, item, link_options = {})
      (raw_content = item.send(attribute)).present? ? raw_content : "&mdash;".html_safe
    end

    def table_selector(attribute, item)
      item.mapping(attribute)
    end

    def table_file_field(attribute, item, link_options = {})
      typus_file_preview(item, attribute)
    end

    def table_tree_field(attribute, item)
      item.parent ? item.parent.to_label : "&mdash;".html_safe
    end

    def table_position_field(attribute, item, connector = " / ")
      html_position = []

      { :move_higher => "Up", :move_lower => "Down" }.each do |key, value|
        options = { :controller => "/admin/#{item.class.to_resource}", :action => "position", :id => item.id, :go => key }
        first_or_last = (item.respond_to?(:first?) && (key == :move_higher && item.first?)) || (item.respond_to?(:last?) && (key == :move_lower && item.last?))
        html_position << link_to_unless(first_or_last, _t(value), params.merge(options)) do |name|
          raw %(<span class="inactive">#{name}</span>)
        end
      end

      html_position.join(connector).html_safe
    end

    def table_datetime_field(attribute, item, link_options = {})
      if field = item.send(attribute)
        I18n.localize(field, :format => item.class.typus_date_format(attribute))
      end
    end

    def table_boolean_field(attribute, item)
      status = item.send(attribute)
      boolean_hash = item.class.typus_boolean(attribute).invert
      human_boolean = status ? boolean_hash["true"] : boolean_hash["false"]

      options = { :controller => "/admin/#{item.class.to_resource}",
                  :action => "toggle",
                  :id => item.id,
                  :field => attribute.gsub(/\?$/, '') }
      confirm = _t("Change %{attribute}?", :attribute => item.class.human_attribute_name(attribute).downcase)
      link_to _t(human_boolean), options, :confirm => confirm
    end

    def table_transversal(attribute, item)
      _attribute, virtual = attribute.split(".")
      item.send(_attribute).send(virtual)
    end

  end

end
