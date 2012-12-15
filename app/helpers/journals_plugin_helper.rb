module JournalsPluginHelper
  
  def html_column_content(column, journal)
    value = column.value(journal)
    case value.class.name
    when 'String'
      if column.name == :subject  # Changed for Journal
        link_to(h(value), :controller => 'issues', :action => 'show', :id => journal.issue)
      else
        h(value)
      end
    when 'Time'
      format_time(value)
    when 'Date'
      format_date(value)
    when 'Fixnum', 'Float'
      if column.name == :done_ratio
        progress_bar(value, :width => '80px')
      else
        h(value.to_s)
      end
    when 'User'
      link_to_user value
    when 'Project'
      link_to_project value
    when 'Version'
      link_to(h(value), :controller => 'versions', :action => 'show', :id => value)
    when 'TrueClass'
      l(:general_text_Yes)
    when 'FalseClass'
      l(:general_text_No)
    when 'Issue'
      link_to_issue(value, :subject => false)
    else
      h(value)
    end
  end
  
end