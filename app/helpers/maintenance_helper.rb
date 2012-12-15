module MaintenanceHelper
  include ApplicationHelper

  def retrieve_query_journal
    if !params[:siderbar_query].blank?
      @query = QueryJournal.new(:name => "_")
      @query.project = nil
      
      if params[:siderbar_query] == "unit"
        check_tracker_filters(@query)
        check_project_custom_filters(@query)
        a = Attachment.find(:first, :conditions =>{:container_id => @container_id, :container_type => "Setting", :description => "unit"})
        if a.nil?
          session[:template] = nil
        else
          session[:template] = { :id => a.id, :type => "unit" }
        end
      elsif params[:siderbar_query] == "worker"
        check_tracker_filters(@query)
        if User.current.logged?
          @query.add_short_filter "user_id", User.current.id.to_s
        else
          @query.add_short_filter "user_id", User.find(:first).id.to_s
        end
        a = Attachment.find(:first, :conditions =>{:container_id => @container_id, :container_type => "Setting", :description => "worker"})
        if a.nil?
          session[:template] = nil
        else
          session[:template] = { :id => a.id, :type => "worker" }
        end
      else
        session[:template] = nil
      end
      
      unless params[:siderbar_query] == "all"
        date_to ||= Date.today.at_beginning_of_month.next_month
        date_from = Date.today.at_beginning_of_month
        @query.add_filter "created_on", "><", [date_from.to_s, date_to.to_s]
      end
      
      show_project_custom_fields(@query)
      session[:query_journal] = nil
    elsif params[:set_filter] || session[:query_journal].nil? || session[:query_journal][:project_id] != nil
      # Give it a name, required to be valid
      # puts "in the block where session[:query_journal] do not exit!"
      @query = QueryJournal.new(:name => "_")
      @query.project = nil
      
      unless params[:set_filter]
        date_to ||= Date.today.at_beginning_of_month.next_month
        date_from = Date.today.at_beginning_of_month
        @query.add_filter "created_on", "><", [date_from.to_s, date_to.to_s]
        session[:template] = nil
      end
      
      build_query_from_params
      show_project_custom_fields(@query)
      
      session[:query_journal] = {:project_id => @query.project_id, :filters => @query.filters, :group_by => @query.group_by, :column_names => @query.column_names}
    else
      # puts "in the block where session[:query_journal] already exit!"
      @query ||= QueryJournal.new(:name => "_", :filters => session[:query_journal][:filters], :group_by => session[:query_journal][:group_by], :column_names => session[:query_journal][:column_names])
      @query.project = nil
    end
  end
  
  def link_to_template(attachment)
    # Use truncate in case of filename too long!!
    link_to(truncate(h(attachment.filename)),
          {:controller => 'maintenance', :action => 'download', :id => attachment, :filename => attachment.filename },
           :class => 'icon icon-attachment')
  end
  
#===========================(tracker_names)=====================================
  def check_tracker_filters(query)
    # check the tracker_filters maintenance needed!!
    tracker_names = Setting["plugin_redmine_maintenance"][:setting_tracker_names]
    new_values = []
    new_values = tracker_names.collect do |name|
      query.available_filters["tracker_id"][:values].find { |value| value[0] == name }
    end.compact unless tracker_names.nil?
    if !new_values.empty?
      # if not empty, show the tracker filters only maintenance needed!!
      # query.available_filters["tracker_id"][:values] = new_values
      query.add_filter "tracker_id", "=", new_values.collect { |tracker| tracker[1] }
    end
  end
  
#=========================(issue_custom_field_names)============================
  def check_project_custom_filters(query)
    issue_custom_fields = Setting["plugin_redmine_maintenance"][:setting_custom_field_names]
    issue_custom_filters = []
    unless issue_custom_fields.nil?
      issue_custom_filters = query.available_filters.find_all { |filter| filter[0] =~ /^pcf_(\d+)$/ && issue_custom_fields.include?(filter[1][:name]) }
    end
    # puts issue_custom_filters
    issue_custom_filters.each do |filter|
      # puts filter[1][:values].class
      if !filter[1][:values].nil?
        query.add_short_filter filter[0], filter[1][:values][0]
      else
        query.add_short_filter filter[0], "请输入用户单位"
      end
    end
  end
  
  def show_project_custom_fields(query)
    # check the issue_custom_fields maintenance needed!!
    project_custom_fields = Setting["plugin_redmine_maintenance"][:setting_custom_field_names]
    custom_column_names = []
    query.available_columns.each do |column|
      if column.is_a?(QueryCustomFieldColumn) && column.custom_field.is_a?(ProjectCustomField) && project_custom_fields.include?(column.caption)
        custom_column_names << column.name
      end
    end unless project_custom_fields.nil?
    # puts custom_column_names
    unless custom_column_names.empty?
      # added the custom_columns at the last by names
      if query.column_names.nil?
        query.column_names = query.default_columns_names + custom_column_names
      else
        query.column_names = query.column_names | custom_column_names
      end
    end
  end
  
end
