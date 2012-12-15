require 'redmine'

Redmine::Plugin.register :redmine_maintenance do
  name 'Redmine Maintenance plugin'
  author 'stardust'
  description 'This is a plugin for Redmine'
  version '0.0.1'
  url 'http://example.com/path/to/plugin'
  author_url 'http://example.com/about'
  
  settings :default => {
    :setting_tracker_names => [], 
    :setting_custom_field_names => ["用户单位"],
  } # :partial => 'maintenance_settings/maintenance_settings'
  
  # permission :maintenance, { :maintenance => :index }, :public => true
  # menu :application_menu, :maintenance, { :controller=>'maintenance', :action=>'index' }, :caption=>'maintenance'
  menu :top_menu, :maintenance, { :controller => 'maintenance', :action => 'index' }, :caption => '任务汇总', 
  :if => Proc.new { User.current.logged? }
end
