# contains methods and logic to be added to classes that call the acts_as_lookup
# method
#-------------------------------------------------------------------------------
module ActsAsLookupClassMethods
  def self.extended(klass)
    klass.send(:instance_variable_set, :@acts_as_lookup_options, nil)
    klass.send(:instance_variable_set, :@acts_as_lookup_by_id, {})
    klass.send(:instance_variable_set, :@acts_as_lookup_by_name, {})
    klass.send(:instance_variable_set, :@acts_as_lookup_initialized, false)
    klass.send(:instance_variable_set, :@acts_as_lookup_values, [])
  end

  def acts_as_lookup_options=(options)
    @acts_as_lookup_options = options
  end
  def acts_as_lookup_options
    @acts_as_lookup_options
  end

  # FUTURE: allow for dynamically specifying which columns can be used for
  #         cache lookups
  #-----------------------------------------------------------------------------
  def lookup_by_id(id)
    @acts_as_lookup_by_id[id]
  end
  def lookup_by_name(name)
    @acts_as_lookup_by_name[name]
  end


  # check if the current lookup class has been initialized for lookup use
  #-----------------------------------------------------------------------------
  def acts_as_lookup_initialized?
    @acts_as_lookup_initialized
  end


  # initialize the current lookup class for lookup use if it isn't already
  #
  # NOTE: early edition of this gem assumes id, name columns. FUTURE will allow
  #       more flexibility through configuration
  #-----------------------------------------------------------------------------
  def acts_as_lookup_initialize
    Thread.exclusive do
      # double-check in case of race condition in calling code
      unless self.acts_as_lookup_initialized?
        if acts_as_lookup_options[:sync_with_db]
          acts_as_lookup_fetch_values
          if acts_as_lookup_options[:write_to_db]
            acts_as_lookup_write_missing_values
          end
        else
          @acts_as_lookup_values = acts_as_lookup_options[:values]
          self.acts_as_lookup_refresh_caches
        end

        @acts_as_lookup_initialized = true
      end

      # FUTURE: allow for a different column to be used for generating class
      #         accessor methods
      @acts_as_lookup_by_name.each_pair do |name,val|
        if acts_as_lookup_options[:add_query_methods]
          self.acts_as_lookup_add_query_method name
        end
        self.acts_as_lookup_add_shortcut name
      end

    end
  end


  # fetches existing records from the db and merges them into the cached values
  # only called if :sync_with_db option is true
  #
  # FUTURE: if this gem is to be used outside of a Rails' ActiveRecord::Base
  # descendant, will need to allow calling class to specify an alternative
  # implementation (maybe add a config value that specifies a method to
  # call)
  #-----------------------------------------------------------------------------
  def acts_as_lookup_fetch_values
    @acts_as_lookup_values = self.all
    self.acts_as_lookup_refresh_caches
  end


  # writes any missing values to the db
  # only called if :sync_with_db and :write_to_db options are both true
  #
  # NOTE: does NOT overwrite any values found in the db, so it is possible for
  #       the values specified in the class to be superceded by values in the
  #       database
  #-----------------------------------------------------------------------------
  def acts_as_lookup_write_missing_values
    # FUTURE: if :ids aren't provided, use the uniqueness_column to determine
    #         which values are missing from existing caches
    acts_as_lookup_options[:values].each do |val|
      next if @acts_as_lookup_by_id.include?(val[:id])

      # bypass attr_accessible protection, assign attributes one-by-one
      new_val = self.new
      val.each_pair do |attr,value|
        setter = "#{attr.to_s}=".to_sym
        if new_val.respond_to?(setter)
          new_val.send(setter, value)
        end
      end
      new_val.save!

      @acts_as_lookup_values << new_val
    end

    self.acts_as_lookup_refresh_caches
  end


  # updates the lookup cache hashes from @@acts_as_lookup_values
  #-----------------------------------------------------------------------------
  def acts_as_lookup_refresh_caches
    # FUTURE: this will get cleaned up, and will dynamically select which
    #         columns to establish lookup caches for.
    @acts_as_lookup_values.each do |val|
      @acts_as_lookup_by_id.merge!(val.id => val) unless @acts_as_lookup_by_id.include?(val.id)
      @acts_as_lookup_by_name.merge!(val.name => val) unless @acts_as_lookup_by_name.include?(val.name)
    end
  end


  # adds a class method to access a particular lookup value via a shortcut
  # method
  #
  # FUTURE: will allow for any column to be used here; for now, hardcoded
  #       to lookup by name
  #-----------------------------------------------------------------------------
  def acts_as_lookup_add_shortcut(name)
    method_name = get_method_name(name)
    if respond_to?(method_name.to_sym)
      raise "Cannot create method '#{method_name}' to #{self.inspect} " +
            "as it conflicts with existing method with same name"
    end

    instance_eval "def #{method_name}; self.lookup_by_name '#{name}'; end"
  end

  # adds an instance method of the form [lookup_value_name]? to check the
  # identity of a lookup object
  #-----------------------------------------------------------------------------
  def acts_as_lookup_add_query_method(lookup_name)
    method_name = "#{get_method_name(lookup_name)}?"
    if respond_to?(method_name.to_sym)
      raise "Cannot create method '#{method_name}?' to #{self.inspect} " +
            "as it conflicts with existing method with same name"
    end

    define_method(method_name) { self.name == lookup_name }
  end

  private

  # does the following transformations:
  #  - converts spaces to underscores
  #  - downcases entire method name unless the constant is already all caps,
  #    in which case, leaves method name in all caps
  #  - checks for name conflicts and raises exception if the shortcut method
  #    name collides with existing method
  #-----------------------------------------------------------------------------
  def get_method_name(name)
    method_name = name.gsub(/ /, '_')
    unless method_name.upcase == method_name
      method_name.downcase!
    end
    method_name
  end
end


# modify object to allow any class to act like a lookup class
#------------------------------------------------------------------------------
class Object

  # converts the calling class to act like a lookup model.
  #
  # NOTE: for now, the values' name column should not have spaces in it,
  #       for cleanliness, though this can be addressed by gsubbing.
  #-----------------------------------------------------------------------------
  def self.acts_as_lookup(options = {})
    self.extend ActsAsLookupClassMethods

    options.merge!(:sync_with_db => true) unless options.include?(:sync_with_db)
    options.merge!(:write_to_db => true) unless options.include?(:write_to_db)
    options.merge!(:add_query_methods => false) unless options.include?(:add_query_methods)
# FUTURE:
#                           :remove_from_db => false,
#                           :shortcut_method_column => :name

    self.acts_as_lookup_options = options

    # lazy initialize? but for now explicitly initialize here
    self.acts_as_lookup_initialize
  end

end

# class methods for ActiveRecord associations
if defined?(ActiveRecord)
  module ActsAsLookupHasLookupClassMethods

    # create an association from the current rails model to a lookup model,
    # providing a name for the association (default will assume the
    # association name follows rails association naming conventions).
    #
    # options:
    #  :class_name: override the default assumption of class name from
    #               +assocaition_name+ argument and explicitly pass in the
    #               classname (in CamelCase) for the association.
    #---------------------------------------------------------------------------
    def has_lookup(association_name, options = {})
      cname = options[:class_name] || association_name.to_s.camelize

      force_class_load cname

      # this is inspired/borrowed from Rapleaf's has_rap_enum
      klass = Kernel.const_get(cname)
      unless(klass && klass.is_a?(ActsAsLookupClassMethods))
        raise "#{cname.to_s.camelize} is not an acts_as_lookup class"
      end

      # create the reader method for the lookup association
      define_method(association_name) do
        klass.lookup_by_id(send("#{association_name}_id"))
      end

      # create the writer method for the lookup association
      define_method("#{association_name}=") do |assoc|
        unless (assoc.class.name == klass.name) || assoc.nil?
          raise "Argument not of type #{klass.name}"
        end
        send("#{association_name}_id=", assoc && assoc.id)
      end
    end

    # separate the logic for forcing a class load to isolate it, as well as
    # making testing easier
    #---------------------------------------------------------------------------
    def force_class_load(cname)
      # this is a hack that is not at all pretty but seems to get around the
      # double-class loading problems that arise in rails: see for example
      # https://rails.lighthouseapp.com/projects/8994/tickets/1339
      # it may create other problems though, so be careful....
      rails_root = nil
      begin
        rails_root = Rails.root
      rescue
      end
      # fallback for Rails 2
      rails_root ||= RAILS_ROOT if defined?(RAILS_ROOT)
      if !Object.const_defined?(cname)
        require File.join(rails_root, 'app', 'models', cname.underscore)
      end
    end
  end

  ActiveRecord::Base.extend ActsAsLookupHasLookupClassMethods

end
