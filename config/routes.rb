ActionController::Routing::Routes.draw do |map|
  map.connect 'maintenance.:format', :controller => 'maintenance', :action => 'index'
  map.connect 'word_export.:format', :controller => 'maintenance', :action => 'word_export'
end
