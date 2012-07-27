require 'spec_helper'

module ActiveRecord
  class Base

  end
end

# add a helper method that's defined in rails...the gem only uses it if
# ActiveRecord is defined
class String
  def camelize
    splits = self.split("_")
    splits.map! do |s|
      s.downcase!
      s[0] = s[0].upcase
      s
    end
    splits.join
  end
end

# a dummy lookup class (see has_lookup tests)
class DummyLookup < Struct.new(:id, :name)
  def self.one_instance
    self.new(1,"dummy one")
  end

  def self.another_instance
    self.new(2,"dummy two")
  end

  def self.yet_another_instance
    self.new(3,"dummy three")
  end
end

describe "ActsAsLookup" do
  # this is kinda hacky, but what we're doing here is trying to clear out all
  # entries in namespace for acts as lookup between each run so that we don't
  # see any bugs that are tied to double-loading the acts as lookup
  # infrastructure
  # so we:
  #   - unload all classes that are either part of gem or are test classes
  #   - reload the acts as lookup lib file
  #   - re-declare each of the test classes we're using
  #
  # (alternative would be to generate new classes for each test but that's
  # likely equally messy with dynamically defined class names etc.)
  #-----------------------------------------------------------------------------
  before :each do
    Object.constants.each do |klass|
      if (klass.to_s =~ /LookupClass/) && (Object.const_defined?(klass.to_s))
        Object.send(:remove_const,klass.to_s)
      end
    end
    load File.join(File.dirname(__FILE__), '../lib/acts_as_lookup.rb')

    class ClassOnlyLookupClass < Struct.new(:id, :name); end

    # another one to detect shared var conflict
    class SecondClassOnlyLookupClass < Struct.new(:id, :name); end

    # all values are in db and in class specification
    class ActiveRecordLookupClassWithAllValuesInDbAndClass < Struct.new(:id, :name)
      ALL_VALUES = [self.new(1, "one"), self.new(2, "two")]

      def self.all_values
        ALL_VALUES
      end

      def self.class_vals
        all_values
      end

      def self.all
        all_values
      end
    end
    # some values are in db; the rest are in class specification
    class ActiveRecordLookupClassWithSomeValuesInDb < Struct.new(:id, :name)
      ALL_VALUES = [self.new(1, "one"), self.new(2, "two"), self.new(3, "three")]

      def self.all_values
        ALL_VALUES
      end

      def self.db_missing_val
        all_values[1]
      end

      def self.class_vals
        all_values
      end

      # don't return all vals in query
      def self.all
        all_values.reject { |v| v.id == db_missing_val.id }
      end

      # a method for checking what's saved when save! is called
      def self.created_val(val)
        # doesn't need to do anything
      end

      # "active record" method for creating new lookup values
      def save!
        self.class.created_val(self)
      end
    end
    # all values in db; some are in class specification
    class ActiveRecordLookupClassWithSomeValuesInClass < Struct.new(:id, :name)
      ALL_VALUES = [self.new(1, "one"), self.new(2, "two"), self.new(3, "three")]

      def self.all_values
        ALL_VALUES
      end

      def self.class_missing_val
        all_values[1]
      end

      def self.class_vals
        all_values.reject { |v| v.id == class_missing_val.id }
      end

      # return all vals in query
      def self.all
        all_values
      end
    end
    class ClassWithLookupClass < ActiveRecord::Base
      attr_accessor :dummy_lookup_id
      attr_accessor :other_lookup_id
    end

  end

  #-----------------------------------------------------------------------------
  describe "class-only (non ActiveRecord) lookup classes" do
    it "should not insert any new values if :write_to_db is false" do
      klass = ClassOnlyLookupClass
      klass.should_not_receive :acts_as_lookup_write_missing_values
      instances = [klass.new(1, "one"), klass.new(2, "two")]

      klass.acts_as_lookup(
        :sync_with_db => false,
        :values => instances
      )
    end

    it "should not query values if :sync_with_db is false" do
      klass = ClassOnlyLookupClass
      klass.should_not_receive :all
      instances = [klass.new(1, "one"), klass.new(2, "two")]

      klass.acts_as_lookup(
        :sync_with_db => false,
        :values => instances
      )
    end

    it "should define query methods if :add_query_methods is true" do
      klass = ClassOnlyLookupClass
      klass.should_not_receive :all
      instances = [klass.new(1, "one"), klass.new(2, "two")]

      klass.acts_as_lookup(
        :add_query_methods => true,
        :sync_with_db => false,
        :values => instances
      )

      klass.one.one?.should be_true
      klass.one.two?.should be_false
    end

    it "should not define query methods if :add_query_methods is false" do
      klass = ClassOnlyLookupClass
      klass.should_not_receive :all
      instances = [klass.new(1, "one"), klass.new(2, "two")]

      klass.acts_as_lookup(
        :add_query_methods => false,
        :sync_with_db => false,
        :values => instances
      )

      klass.one.one?.should raise_error
    end
  end

  # "active record" tests
  # note: these test classes aren't really active record classes (to enable
  #       testing in absence of active record), but mimic enough of the
  #       interface for the tests

  #-----------------------------------------------------------------------------
  describe "when active record lookup class specifies all values and db has all values" do
    it "should run select query if :sync_with_db is true" do
      klass = ActiveRecordLookupClassWithAllValuesInDbAndClass

      klass.should_receive(:all).and_return klass.all_values

      klass.acts_as_lookup(
        :values => klass.class_vals
      )
    end

    it "should not insert any new values even if :write_to_db is true" do
      klass = ActiveRecordLookupClassWithAllValuesInDbAndClass

      klass.should_not_receive(:new)

      klass.acts_as_lookup(
        :write_to_db => true,
        :values => klass.class_vals
      )
    end

    it "should return correct value accessed by lookup_by_id" do
      klass = ActiveRecordLookupClassWithAllValuesInDbAndClass
      klass.acts_as_lookup(
        :write_to_db => true,
        :values => klass.class_vals
      )

      klass.lookup_by_id(klass.all_values.first.id).should == klass.all_values.first
    end

    it "should return correct value accessed by lookup_by_name" do
      klass = ActiveRecordLookupClassWithAllValuesInDbAndClass
      klass.acts_as_lookup(
        :write_to_db => true,
        :values => klass.class_vals
      )

      klass.lookup_by_name(klass.all_values.last.name).should == klass.all_values.last
    end
  end

  #-----------------------------------------------------------------------------
  describe "when lookup class specifies all lookup values but db only specifies some" do
    before :each do
      @klass = ActiveRecordLookupClassWithSomeValuesInDb
    end

    it "should run select query if :sync_with_db is true" do
      all_result = @klass.all

      @klass.should_receive(:all).and_return all_result

      @klass.acts_as_lookup(
        :values => @klass.class_vals
      )
    end

    it "should insert any new values when :write_to_db is true" do
      # this is a dummy class method that gets called when instance method
      # save! is called, so we can check what was created
      @klass.should_receive(:created_val) { |val|
        val.id.should == @klass.db_missing_val.id
        val.name.should == @klass.db_missing_val.name
      }

      @klass.acts_as_lookup(
        :write_to_db => true,
        :values => @klass.class_vals
      )
    end

    it "should return correct value accessed by lookup_by_id" do
      @klass.acts_as_lookup(
        :write_to_db => true,
        :values => @klass.class_vals
      )

      @klass.lookup_by_id(@klass.db_missing_val.id).should == @klass.db_missing_val
    end

    it "should return correct value accessed by lookup_by_name" do
      @klass.acts_as_lookup(
        :write_to_db => true,
        :values => @klass.class_vals
      )

      @klass.lookup_by_name(@klass.db_missing_val.name).should == @klass.db_missing_val
    end
  end

  #-----------------------------------------------------------------------------
  describe "when lookup class doesn't specify all lookup values but db does" do
    before :each do
      @klass = ActiveRecordLookupClassWithSomeValuesInClass
    end

    it "should run select query if :sync_with_db is true" do
      all_result = @klass.all

      @klass.should_receive(:all).and_return all_result

      @klass.acts_as_lookup(
        :values => @klass.class_vals
      )
    end

    it "shouldn't insert any new values even if :write_to_db is true" do
      @klass.should_not_receive(:new)

      @klass.acts_as_lookup(
        :write_to_db => true,
        :values => @klass.class_vals
      )
    end

    it "should return correct value accessed by lookup_by_id" do
      @klass.acts_as_lookup(
        :write_to_db => true,
        :values => @klass.class_vals
      )

      @klass.lookup_by_id(@klass.class_missing_val.id).should == @klass.class_missing_val
    end

    it "should return correct value accessed by lookup_by_name" do
      @klass.acts_as_lookup(
        :write_to_db => true,
        :values => @klass.class_vals
      )

      @klass.lookup_by_name(@klass.class_missing_val.name).should == @klass.class_missing_val
    end
  end

  #-----------------------------------------------------------------------------
  describe "single-lookup-class scenarios" do
    before :each do
      @klass = ActiveRecordLookupClassWithSomeValuesInClass
      @klass.acts_as_lookup(:values => @klass.class_vals)
    end

    it "should not query values on calls to lookup_by_id" do
      @klass.should_not_receive(:find)
      @klass.should_not_receive(:find_by_id)

      @klass.lookup_by_id(1)
    end

    it "should not query values calls to lookup_by_name" do
      @klass.should_not_receive(:find)
      @klass.should_not_receive(:find_by_name)

      @klass.lookup_by_name('one')
    end

    it "should dynamically add specific methods to access lookup value by name" do
      @klass.all_values.each do |val|
        @klass.send(val.name.to_sym).should == val
      end
    end
  end

  describe "two-lookup-class scenarios" do
    it "should return the correct object (type) even if ids overlap between two lookup classes" do
      klass1 = ClassOnlyLookupClass
      klass2 = SecondClassOnlyLookupClass
      instances1 = [klass1.new(1, "one"), klass1.new(2, "two")]
      instances2 = [klass2.new(1, "class two one"), klass2.new(2, "class two two")]
      klass1.acts_as_lookup(
        :sync_with_db => false,
        :values => instances1
      )
      klass2.acts_as_lookup(
        :sync_with_db => false,
        :values => instances2
      )

      klass1.lookup_by_id(1).should == instances1.first
      klass2.lookup_by_id(1).should == instances2.first
    end

    it "should return the correct object (type) even if names overlap between two lookup classes" do
      klass1 = ClassOnlyLookupClass
      klass2 = SecondClassOnlyLookupClass
      instances1 = [klass1.new(3, "three"), klass1.new(4, "four")]
      instances2 = [klass2.new(33, "three"), klass2.new(44, "four")]
      klass1.acts_as_lookup(
        :sync_with_db => false,
        :values => instances1
      )
      klass2.acts_as_lookup(
        :sync_with_db => false,
        :values => instances2
      )

      klass1.lookup_by_name('four').should == instances1.last
      klass2.lookup_by_name('four').should == instances2.last
    end

    it "should keep acts as lookup options separate for different lookup classes" do
      klass1 = ClassOnlyLookupClass
      klass2 = SecondClassOnlyLookupClass
      instances1 = [klass1.new(1, "one"), klass1.new(2, "two")]
      instances2 = [klass2.new(3, "three"), klass2.new(4, "four")]
      klass1.acts_as_lookup(
        :sync_with_db => false,
        :values => instances1
      )
      klass2.acts_as_lookup(
        :sync_with_db => false,
        :values => instances2
      )

      klass1.acts_as_lookup_options[:values].should == instances1
      klass2.acts_as_lookup_options[:values].should == instances2
    end
  end

  describe "when using has_lookup to associate classes" do
    it "should not make a db hit to look up a single record when accessing a has_lookup accessor" do
      DummyLookup.acts_as_lookup(
        :values => [DummyLookup.one_instance],
        :sync_with_db => false
      )
      klass = ClassWithLookupClass
      klass.has_lookup :dummy_lookup
      lookup_instance = DummyLookup.one_instance

      instance = klass.new
      instance.dummy_lookup_id = lookup_instance.id

      instance.dummy_lookup.should == lookup_instance
    end

    it "should set the id attribute of an object that has_lookup when the whole-object setter is used" do
      DummyLookup.acts_as_lookup(
        :values => [DummyLookup.another_instance],
        :sync_with_db => false
      )
      klass = ClassWithLookupClass
      klass.has_lookup :dummy_lookup
      lookup_instance = DummyLookup.one_instance

      instance = klass.new
      instance.dummy_lookup = lookup_instance

      instance.dummy_lookup_id.should == lookup_instance.id
    end

    it "should allow overriding the class name on a has_lookup association" do
      DummyLookup.acts_as_lookup(
        :values => [DummyLookup.yet_another_instance],
        :sync_with_db => false
      )
      klass = ClassWithLookupClass
      klass.has_lookup :other_lookup, :class_name => 'DummyLookup'
      lookup_instance = DummyLookup.one_instance

      instance = klass.new
      instance.other_lookup = lookup_instance

      instance.other_lookup_id.should == lookup_instance.id
    end
  end
end
