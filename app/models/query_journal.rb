require "query.rb"

class QueryJournalColumn < QueryColumn
  # return objects for the name
  def value(journal)
    if journal.respond_to?(name)
      journal.send name
    # two level search for issue
    elsif journal.issue.respond_to?(name)
      journal.issue.send name
    end
  end
  
end

class QueryJournalCustomFieldColumn < QueryCustomFieldColumn
  def initialize(custom_field)
    super custom_field
    if @cf.is_a?(ProjectCustomField)
      self.name = "pcf_#{custom_field.id}".to_sym
    end
  end
  
  def value(journal)
    if @cf.is_a?(IssueCustomField)
      cv = journal.issue.custom_values.detect {|v| v.custom_field_id == @cf.id}
      cv && @cf.cast_value(cv.value)
    elsif @cf.is_a?(ProjectCustomField)
      cv = journal.issue.project.custom_values.detect {|v| v.custom_field_id == @cf.id}
      cv && @cf.cast_value(cv.value)
    end
  end
  
end

class QueryJournal < Query
  # overwrite the @@available_columns
  @journal_available_columns = [
    QueryJournalColumn.new(:project, :sortable => "#{Project.table_name}.name"),
    QueryJournalColumn.new(:issue, :sortable => "#{Issue.table_name}.id"),
    QueryJournalColumn.new(:subject, :sortable => "#{Issue.table_name}.subject"),
    QueryJournalColumn.new(:notes, :caption => :query_journal_notes, :sortable => "#{Journal.table_name}.notes"),
    QueryJournalColumn.new(:user, :caption => :query_journal_user, :sortable => "#{User.table_name}.id"),
    QueryJournalColumn.new(:created_on, :caption => :query_journal_created_on, :sortable => "#{Journal.table_name}.created_on", :groupable => true )
  ]
  
  class << self
    attr_accessor :journal_available_columns
  end
  
  def initialize(attributes = nil)
    super attributes
    self.filters['status_id'] = {:operator => "*", :values => [""]}
  end
  
  def available_filters
    return @available_filters if @available_filters
    @available_filters = super
    
    author_values = []
    author_values += User.find(:all).collect{|s| [s.name, s.id.to_s] }
    @available_filters["created_on"] = { :name => l(:query_journal_created_on), :type => :date_past, :order => 21 }
    @available_filters["user_id"] = { :name => l(:query_journal_user), :type => :list, :order => 21, :values => author_values }
    @available_filters["notes"] = { :name => l(:query_journal_notes), :type => :text, :order => 21 }
    add_project_custom_fields_filters(ProjectCustomField.find(:all))
    @available_filters
  end
  
  def available_columns
    return @available_columns if @available_columns
    @available_columns = ::QueryJournal.journal_available_columns
    
    # find custom_fields for Issue to be added!!
    @available_columns += (project ?
                            project.all_issue_custom_fields :
                            IssueCustomField.find(:all)
                           ).collect {|cf| QueryJournalCustomFieldColumn.new(cf) }
    # find project_custom_fiedls for Project to be added!!
    @available_columns += ProjectCustomField.find(:all).collect {|cf| QueryJournalCustomFieldColumn.new(cf) }
  end
  
  # Returns a Hash of columns and the key for sorting
  def sortable_columns
    {'id' => "#{Journal.table_name}.id"}.merge(available_columns.inject({}) {|h, column|
                                               h[column.name.to_s] = column.sortable
                                               h
                                             })
  end
  
  def default_columns_names
    @default_columns_names ||= begin
      default_columns = [ :issue, :subject, :notes, :user, :created_on ]

      project.present? ? default_columns : [:project] | default_columns
    end
  end
  
  def group_by_timestamp
    ::QueryJournal.journal_available_columns.detect {|c| c.groupable && c.name.to_s == "created_on"}
  end
  
  def statement
    # filters clauses
    filters_clauses = []
    filters.each_key do |field|
      next if field == "subproject_id"
      v = values_for(field).clone
      next unless v and !v.empty?
      operator = operator_for(field)

      # "me" value subsitution
      if %w(assigned_to_id author_id watcher_id).include?(field)
        if v.delete("me")
          if User.current.logged?
            v.push(User.current.id.to_s)
            v += User.current.group_ids.map(&:to_s) if field == 'assigned_to_id'
          else
            v.push("0")
          end
        end
      end

      if field =~ /^cf_(\d+)$/
        # custom field
        filters_clauses << sql_for_custom_field(field, operator, v, $1)
      elsif field =~ /^pcf_(\d+)$/
        filters_clauses << sql_for_project_custom_field(field, operator, v, $1)
      elsif respond_to?("sql_for_#{field}_field")
        # specific statement
        filters_clauses << send("sql_for_#{field}_field", field, operator, v)
      elsif Journal.column_names.include?(field)
        # Added code by duanpeijian to search for Journal!!
        filters_clauses << '(' + sql_for_field(field, operator, v, Journal.table_name, field) + ')'
      else
        # regular field
        filters_clauses << '(' + sql_for_field(field, operator, v, Issue.table_name, field) + ')'
      end
    end if filters and valid?

    filters_clauses << project_statement
    filters_clauses.reject!(&:blank?)

    filters_clauses.any? ? filters_clauses.join(' AND ') : nil
  end
  
  def journal_count
    cond = "#{Journal.table_name}.journalized_type = 'Issue' AND #{Journal.table_name}.notes <> ''"
    Journal.visible.scoped(:conditions => cond).count( :include => [{:issue => [:status, :project]}], 
              :conditions => statement)
  rescue ::ActiveRecord::StatementInvalid => e
    raise StatementInvalid.new(e.message)
  end
  
  def journals_group_by_date
    # every day default order is datetime desc!!
    cond = "#{Journal.table_name}.journalized_type = 'Issue' AND #{Journal.table_name}.notes <> ''"
    date_hash = Journal.visible.scoped(:conditions => cond).find(:all, :include => [{:issue => [:status, :project]}], 
                   :conditions => statement).group_by(&:event_date)
    date_hash
  end
  
  def journal_count_by_date
    count_hash = {}
    journals_group_by_date.each do |key, value|
      count_hash[key] = value.nitems
    end
    count_hash
  end
  
  def journals(options={})
    order_option = ["#{Journal.table_name}.created_on", options[:order]].reject {|s| s.blank?}.join(',')
    order_option = nil if order_option.blank?
    cond = "#{Journal.table_name}.journalized_type = 'Issue' AND #{Journal.table_name}.notes <> ''"
    Journal.visible.scoped(:conditions => cond).find :all, :include => [:user, {:issue => [:status, :project]}], 
                       :conditions => statement,
                       :order => order_option,
                       :limit => options[:limit],
                       :offset => options[:offset]
  rescue ::ActiveRecord::StatementInvalid => e
    raise StatementInvalid.new(e.message)
  end
  
  private
  
  def sql_for_project_custom_field(field, operator, value, custom_field_id)
    db_table = CustomValue.table_name
    db_field = 'value'
    "#{Project.table_name}.id IN (SELECT #{Project.table_name}.id FROM #{Project.table_name} LEFT OUTER JOIN #{db_table} ON #{db_table}.customized_type='Project' AND #{db_table}.customized_id=#{Project.table_name}.id AND #{db_table}.custom_field_id=#{custom_field_id} WHERE " +
      sql_for_field(field, operator, value, db_table, db_field, true) + ')'
  end
  
  def add_project_custom_fields_filters(custom_fields)
    @available_filters ||= {}

    custom_fields.each do |field|
      case field.field_format
      when "text"
        options = { :type => :text, :order => 20 }
      when "list"
        options = { :type => :list_optional, :values => field.possible_values, :order => 20}
      when "date"
        options = { :type => :date, :order => 20 }
      when "bool"
        options = { :type => :list, :values => [[l(:general_text_yes), "1"], [l(:general_text_no), "0"]], :order => 20 }
      when "int"
        options = { :type => :integer, :order => 20 }
      when "float"
        options = { :type => :float, :order => 20 }
      when "user", "version"
        next unless project
        options = { :type => :list_optional, :values => field.possible_values_options(project), :order => 20}
      else
        options = { :type => :string, :order => 20 }
      end
      @available_filters["pcf_#{field.id}"] = options.merge({ :name => field.name })
    end
  end
end