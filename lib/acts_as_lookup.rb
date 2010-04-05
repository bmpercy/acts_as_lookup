# contains methods and logic to be added to classes that call the acts_as_lookup
# method
#-------------------------------------------------------------------------------
module ActsAsLookupClassMethods
  def acts_as_lookup_options=(options)
    @@acts_as_lookup_options = options
  end

  def acts_as_lookup_options
    @@acts_as_lookup_options
  end

  # FUTURE: allow for dynamically specifying which columns can be used for
  #         cache lookups
  #-----------------------------------------------------------------------------
  def lookup_by_id(id)
    @@acts_as_lookup_by_id[id]
  end
  def lookup_by_name(name)
    @@acts_as_lookup_by_name[name]
  end


  # check if the current lookup class has been initialized for lookup use
  #-----------------------------------------------------------------------------
  def acts_as_lookup_initialized?
    if !defined?(@@acts_as_lookup_initialized)
      @@acts_as_lookup_initialized = false
    end

    @@acts_as_lookup_initialized
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
        @@acts_as_lookup_by_id = {}
        @@acts_as_lookup_by_name = {}

        if @@acts_as_lookup_options[:sync_with_db]
          acts_as_lookup_fetch_values
          if @@acts_as_lookup_options[:write_to_db]
            acts_as_lookup_write_missing_values
          end
        else
          @@acts_as_lookup_values = @acts_as_lookup_options[:values]
          self.acts_as_lookup_refresh_caches
        end

        @@acts_as_lookup_initialized = true
      end

      # FUTURE: allow for a different column to be used for generating class
      #         accessor methods
      @@acts_as_lookup_by_name.each_pair do |name,val|
        self.acts_as_lookup_add_shortcut name
      end

    end
  end


  # fetches existing records from the db and merges them into the cached values
  #
  # TODO: if this gem is to be used outside of a Rails' ActiveRecord::Base
  #       descendant, will need to allow calling class to specify an alternative
  #       implementation (maybe add a config value that specifies a method to
  #       call)
  #-----------------------------------------------------------------------------
  def acts_as_lookup_fetch_values
    @@acts_as_lookup_values = self.all
    self.acts_as_lookup_refresh_caches
  end


  # writes any missing values to the db
  #
  # NOTE: does NOT overwrite any values found in the db, so it is possible for
  #       the values specified in the class to be superceded by values in the
  #       database
  #-----------------------------------------------------------------------------
  def acts_as_lookup_write_missing_values

    # FUTURE: if :ids aren't provided, use the uniqueness_column to determine
    #         which values are missing from existing caches
    @@acts_as_lookup_options[:values].each do |val|
      next if @@acts_as_lookup_by_id.include?(val[:id])

      # allow for attr_accessible protection, assign attributes one-by-one
      new_val = self.new
      val.each_pair do |attr,value|
        new_val.send("#{attr.to_s}=".to_sym, value)
      end
      new_val.save!

      @@acts_as_lookup_values << new_val
    end

    self.acts_as_lookup_refresh_caches
  end


  # updates the lookup cache hashes from @@acts_as_lookup_values
  #-----------------------------------------------------------------------------
  def acts_as_lookup_refresh_caches
    @@acts_as_lookup_values.each do |val|
      @@acts_as_lookup_by_id.reverse_merge! val.id => val
    end
    @@acts_as_lookup_values.each do |val|
      @@acts_as_lookup_by_name.reverse_merge! val.name => val
    end
  end


  # adds a class method to access a particular lookup value via a shortcut
  # method
  #
  # TODO: FUTURE will allow for any column to be used here; for now, hardcoded
  #       to lookup by name
  #-----------------------------------------------------------------------------
  def acts_as_lookup_add_shortcut(name)
    instance_eval "def #{name}; self.lookup_by_name '#{name}'; end"
  end

end

class Object

  # converts the calling class to act like a lookup model.
  #
  # NOTE: for now, the values' name column should not have spaces in it,
  #       for cleanliness, though this can be addressed by gsubbing.
  #-----------------------------------------------------------------------------
  def self.acts_as_lookup(options = {})
    self.extend ActsAsLookupClassMethods

    options.reverse_merge! :sync_with_db => true,
                           :write_to_db => true  #,
# TODO: FUTURE
#                           :remove_from_db => false,
#                           :shortcut_method_column => :name

    self.acts_as_lookup_options = options

    # TODO: lazy initialize? but for now explicitly initialize here
    self.acts_as_lookup_initialize
  end

end
