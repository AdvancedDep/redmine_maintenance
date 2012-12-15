module JournalsExportHelper
  
#======================(XML functions)=========================
  def render_xml(issues, options={})
    @items = issues || []
    @items.sort! {|x,y| y.event_datetime <=> x.event_datetime }
    
    # puts "in the render_xml instance method"
    
    render :template => "maintenance/issues.xml", :layout => false,
           :content_type => 'application/xml'
  end
  
  def issues_to_xml(issues, project, query)
    xml = Builder::XmlMarkup.new
    xml.instruct!
    xml.issues do
      xml.title do
        xml.id '#'
        query.columns.each do |column|
          xml.tag! column.name, column.caption
        end
      end
      issues.each do |item|
        xml.issue do
          xml.id item.id
          query.columns.each do |column|
             xml.tag! column.name, issue_column_content(column, item)
          end
        end
      end
    end
  end
  
  def xml_column_content(column, issue)
    value = column.value(issue)
    
    case value.class.name
    when 'Time'
      format_time(value)
    when 'Date'
      format_date(value)
    when 'Fixnum', 'Float'
      value.to_s
    when 'TrueClass'
      l(:general_text_Yes)
    when 'FalseClass'
      l(:general_text_No)
    else
      value
    end
  end
  
  def values_by_operator(query, field, operator)
    case operator
      when "!*","*","t","w","o","c"
        res = nil
      when "><"
        res = query.value_for(field) + query.value_for(field, 1)
      when "<t+",">t+","t+",">t-","<t-","t-"
        res = query.value_for(field)
    end
    res
  end
  
  def filters_to_export(query)
    filter_hash = {}
    filters = query.available_filters.find_all{|filter| query.has_filter?(filter[0])}
    filters.each do |filter|
      field = filter[0]
      options = filter[1]
      filter_name = filter[1][:name] || l(("field_"+field.to_s.gsub(/\_id$/, "")).to_sym)
      filter_operator = query.operator_for(field)
      filter_operator_name = l(Query.operators[filter_operator])
      filter_values = query.values_for(field)
      # filter_hash[field] = filter_name + ":" + filter_operator_name + "(" + filter_values + ")"
      filter_hash[field] = { :name => filter_name, :operator => filter_operator_name, :values => filter_values }
    end
    filter_hash
  end
  
  def journals_to_xml(journals, query)
    # Testing code added by duanpeijian!!
    # p query
    xml = Builder::XmlMarkup.new
    @jounals_by_day = query.journals_group_by_date
    filter_hash = filters_to_export(query)
    date_scope = ""
    if filter_hash["created_on"] && query.operator_for("created_on") == "><"
      date_scope = query.values_for("created_on").join("至")
    end
    xml.instruct!
    xml.query "name" => date_scope do
      
      xml.filters do
        filter_hash.each do |filter|
          # xml.filter filter[1], "name" => filter[0]
          filter[0] = "pcf_unit" if filter[0]=~ /^pcf_(\d+)$/ && query.operator_for(filter[0]) == "=" && filter[1][:name].include?("用户单位")
          xml.filter "name" => filter[0] do
            xml.tag! filter[0] do
              xml.name filter[1][:name]
              xml.operator filter[1][:operator]
              xml.values do
                filter[1][:values].each do |value|
                  xml.value value
                end
              end
            end
          end
        end
      end
      
      xml.issues do
        @jounals_by_day.keys.sort.each do |day|
          xml.group "name" => day, "count" => @jounals_by_day[day].nitems do
            number = 0
            @jounals_by_day[day].sort {|x,y| x.created_on <=> y.created_on }.each do |item|
              number = number + 1
              xml.journal "number" => number do
                xml.id item.id, "name" => "#"
                query.columns.each do |column|
                  column_content = xml_column_content(column, item)
                  if column.name.to_s == "notes"
                    # distinguish the newline of notes
                    a = column_content.split("\r\n")
                    xml.notes "name" => column.caption do
                      xml.first a.shift
                      a.each do |note|
                        xml.note note.strip
                      end
                    end
                  else
                    xml.tag! column.name, column_content, "name" => column.caption
                  end
                end
              end
            end
          end
        end
      end
      
    end
  end
  
end