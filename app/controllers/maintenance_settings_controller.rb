require 'nokogiri'

class MaintenanceSettingsController < ApplicationController
  
  before_filter :find_attachment
  
  helper :maintenance
  include MaintenanceHelper
  
  def index
    if request.post?
      # Not Setting["plugin_redmine_maintenance"]["tracker_names"] = params[:tracker_names]
      unless params[:tracker_names].nil? || params[:project_custom_field_names].nil?
        Setting["plugin_redmine_maintenance"] = { :setting_tracker_names => params[:tracker_names], 
          :setting_custom_field_names => params[:project_custom_field_names].uniq }
      else
        flash[:error] = l(:error_update_failure)
      end
      
      ###################################################################
      if check_attachment_params(params[:attachment_worker]) && check_attachment_params(params[:attachment_unit])
        JournalAttachment.attach_files(@plugin_setting, params[:attachment_worker], "worker")
        render_attachment_warning_if_needed(@plugin_setting)
        JournalAttachment.attach_files(@plugin_setting, params[:attachment_unit], "unit")
        render_attachment_warning_if_needed(@plugin_setting)
      else
        if flash[:error].nil?
          flash[:error] = l(:error_template_format)
        else
          flash[:error] = l(:error_update_failure) + "<br/>" + l(:error_template_format)
        end
      end
      ###################################################################
      
      flash[:notice] = l(:notice_successful_update) if flash[:error].nil?
      redirect_to :controller => "maintenance_settings", :action => 'index'
    else
      @tracker_names = Setting["plugin_redmine_maintenance"][:setting_tracker_names]
      @trackers = Tracker.find(:all, :order => 'position').collect { |tracker| tracker.name }
      # p @tracker_names
      @project_custom_field_names = Setting["plugin_redmine_maintenance"][:setting_custom_field_names]
      @project_custom_fields = ProjectCustomField.find(:all, :order => 'position').collect do |field|
        @unit_custom_field = field.name if field.name.include?("用户单位")
        field.name
      end
      # p @project_custom_field_names
      # p @project_custom_fields
    end
  end
  
private
  def find_attachment
    if Setting.find_by_name("plugin_redmine_maintenance").nil?
      Setting["plugin_redmine_maintenance"] = Setting.available_settings["plugin_redmine_maintenance"]["default"]
    end
    @plugin_setting = JournalSetting.find_by_name("plugin_redmine_maintenance")
    @worker_attachment = Attachment.find(:first, :conditions =>{:container_id => @plugin_setting.id, :container_type => "Setting", :description => "worker"})
    @unit_attachment = Attachment.find(:first, :conditions =>{:container_id => @plugin_setting.id, :container_type => "Setting", :description => "unit"})
  end
  
  def check_attachment_params(attachments)
    if attachments && attachments.is_a?(Hash)
      attachments.each_value do |attachment|
        file = attachment['file']
        filename = sanitize_filename(file.original_filename)
        content_type = file.content_type.to_s.chomp
        if content_type.blank?
          content_type = Redmine::MimeType.of(filename)
        end
        unless content_type == "application/xml" || content_type == "text/xml"
          puts content_type
          return false
        end
        xslt_ns = "http://www.w3.org/1999/XSL/Transform"
        xml_document = Nokogiri::XML.parse(file.read)
        xslt_node = xml_document.xpath("xsl:stylesheet", {"xsl" => xslt_ns}).first
        if xslt_node.nil?
          return false
        end
        file.rewind # This is the most important to reset to the start of file!!
      end
    end
    return true
  end
  
  def sanitize_filename(value)
    # get only the filename, not the whole path
    just_filename = value.gsub(/^.*(\\|\/)/, '')
    # Finally, replace invalid characters with underscore
    just_filename.gsub(/[\/\?\%\*\:\|\"\'<>]+/, '_')
  end
end