class JournalAttachment < Attachment
  # Bulk attaches a set of files to an object
  #
  # Returns a Hash of the results:
  # :files => array of the attached files
  # :unsaved => array of the files that could not be attached
  def self.attach_files(obj, attachments, type)
    attached = []
    
    # puts obj.class
    # Code Added by duanpeijian!!
    unless attachments.nil?
      container_id = obj.id
      temp = Attachment.find(:first, :conditions => {:container_id => container_id, :container_type => "Setting", :description => type})
      obj.attachments.delete(temp) unless temp.nil?
    end
    
    if attachments && attachments.is_a?(Hash)
      attachments.each_value do |attachment|
        # puts attachment['file'].class
        file = attachment['file']
        next unless file && file.size > 0
        
        a = Attachment.create(:container => obj,
                              :file => file,
                              :description => type.to_s.strip,
                              :author => User.current)
        # p obj.attachments
        # in order to trigger :after_add call_back
        obj.attachments << a
        # p obj.attachments
        
        if a.new_record?
          obj.unsaved_attachments ||= []
          obj.unsaved_attachments << a
        else
          attached << a
        end
      end
    end
    {:files => attached, :unsaved => obj.unsaved_attachments}
  end
end