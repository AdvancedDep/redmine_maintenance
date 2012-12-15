require 'nokogiri'

class MaintenanceController < ApplicationController
  # the sequence can't be converted!!
  before_filter :plugin_settings
  before_filter :check_trackers_and_custom_fields, :only => [:index]
  before_filter :find_project, :only => [:download]
  
  helper :maintenance
  include MaintenanceHelper
  helper :sort
  include SortHelper
  helper :custom_fields
  include CustomFieldsHelper
  helper :queries
  include QueriesHelper
  # Helper for Journals
  helper :journals_plugin
  include JournalsPluginHelper
  include JournalsExportHelper
  
  def index
    retrieve_query_journal
    # maintenance_retrieve_query
    sort_init(@query.sort_criteria.empty? ? [['id', 'desc']] : @query.sort_criteria)
    sort_update(@query.sortable_columns)
    
    if @query.valid?
      case params[:format]
      when 'csv', 'pdf'
        @limit = Setting.issues_export_limit.to_i
      when 'atom'
        @limit = Setting.feeds_limit.to_i
      else
        @limit = per_page_option
      end
      
      # Paginator Association Code!!
      @journal_count = @query.journal_count
      @journal_pages = Paginator.new self, @journal_count, @limit, params['page']
      @offset ||= @journal_pages.current.offset
      
      @journals = @query.journals(:order => sort_clause, :offset => @offset, :limit => @limit)
      @journal_count_by_date = @query.journal_count_by_date
      
      respond_to do |format|
        #puts format.class
        format.html { render :template => 'maintenance/index', :layout => !request.xhr? }
        
        # this must be added before the  "format.api" to override the default operation 
        # format.xml  { render_xml(@issues, :title => "#{@project || Setting.app_title}: #{l(:label_issue_plural)}") }
        format.xml  { send_data(journals_to_xml(@journals, @query), :type => 'application/xml', :filename => 'export.xml') }
        format.atom { render_feed(@journals, :title => "#{@project || Setting.app_title}: Journals") }
      end
    else
      respond_to do |format|
        format.html { render(:template => 'maintenance/index', :layout => !request.xhr?) }
        format.any(:atom) { render(:nothing => true) }
      end
    end
  rescue ActiveRecord::RecordNotFound
    render_404
  end
  
  def word_export
    retrieve_query_journal
    # maintenance_retrieve_query
    sort_init(@query.sort_criteria.empty? ? [['id', 'desc']] : @query.sort_criteria)
    sort_update(@query.sortable_columns)
    
    @journals = @query.journals(:order => sort_clause, :offset => @offset, :limit => @limit)
    
    @word_template = Attachment.find(session[:template][:id]) unless session[:template].nil?
    
    if @query.valid? && @word_template
      
      xml_data = journals_to_xml(@journals, @query)
      source = Nokogiri::XML( xml_data )
      begin
        xslt =Nokogiri::XSLT( File.read(@word_template.diskfile) )
      rescue => e
        logger.error "Error during pasing XSLT: #{e.message}" if logger
        return
      end
      
      export_data = xslt.transform(source)
      # send_data(xml_data, :type => 'application/xml', :filename => 'export.xml')
      send_data(export_data.to_s, :type => 'application/xml', :filename => 'word.doc')
    else
      render(:nothing => true)
    end
  end
  
  def download
    # images are sent inline
    send_file @attachment.diskfile, :filename => filename_for_content_disposition(@attachment.filename),
                                    :type => detect_content_type(@attachment),
                                    :disposition => (@attachment.image? ? 'inline' : 'attachment')
  end
  
private
  def find_project
    @attachment = Attachment.find(params[:id])
    # Show 404 if the filename in the url is wrong
    raise ActiveRecord::RecordNotFound if params[:filename] && params[:filename] != @attachment.filename
    @project = nil # modified by duanpeijian!!
  rescue ActiveRecord::RecordNotFound
    render_404
  end
  
  def detect_content_type(attachment)
    content_type = attachment.content_type
    if content_type.blank?
      content_type = Redmine::MimeType.of(attachment.filename)
    end
    content_type.to_s
  end
  
  def plugin_settings
    if Setting.find_by_name("plugin_redmine_maintenance").nil?
      Setting["plugin_redmine_maintenance"] = Setting.available_settings["plugin_redmine_maintenance"]["default"]
    end
    @container_id = JournalSetting.find_by_name("plugin_redmine_maintenance").id
    @worker_attachment = Attachment.find(:first, :conditions =>{:container_id => @container_id, :container_type => "Setting", :description => "worker"})
    @unit_attachment = Attachment.find(:first, :conditions =>{:container_id => @container_id, :container_type => "Setting", :description => "unit"})
  end
  
  def check_trackers_and_custom_fields
    # initialize the error hash!!
    @error_hash = {}
    # find trackers
    tracker_names = Setting["plugin_redmine_maintenance"][:setting_tracker_names]
    tracker_missing = []
    tracker_names.each do |tracker_name|
      if Tracker.find_by_name(tracker_name).nil? # Testing!!
        tracker_missing << tracker_name
      end
    end unless tracker_names.nil?
    # p tracker_missing
    unless tracker_missing.empty?
      # error_collect("tracker_missing", tracker_missing)
      @error_hash["tracker_missing"] = tracker_missing
    end
    # find issue_custom_fields
    project_custom_field_names = Setting["plugin_redmine_maintenance"][:setting_custom_field_names]
    custom_field_missing = []
    project_custom_field_names.each do |custom_field_name|
      if ProjectCustomField.find_by_name(custom_field_name).nil? # Testing!!
        custom_field_missing << custom_field_name
      end
    end unless project_custom_field_names.nil?
    unless custom_field_missing.empty?
      # error_collect("custom_field_missing", custom_field_missing)
      @error_hash["custom_field_missing"] = custom_field_missing
    end
    
    # Added by the last!!
    # p @error_hash
    unless @error_hash.empty?
      render :template => "validates/index"
      return
    end
  end
end
