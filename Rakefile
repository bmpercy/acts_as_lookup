require 'rake'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gemspec|
    gemspec.name = "acts_as_lookup"
    gemspec.summary = "Helpful for creating lookup-table-like models"
    gemspec.description = <<DESC
Provides an easy means for creating models that act like enumerations or lookup
tables. You can specify the lookup values in your Rails models and can lazily
push these to the associated db tables (or not). Also dynamically adds helpful
class-level methods to access singleton instances of each value in your lookup
table.
DESC
    gemspec.email = "percivalatumamibuddotcom"
    gemspec.homepage = "http://github.com/bmpercy/acts_as_lookup"
    gemspec.authors = ['Brian Percival']
    gemspec.files = ["acts_as_lookup.gemspec",
                     "[A-Z]*.*",
                     "lib/**/*.rb"]
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler not available. Install it with: sudo gem install technicalpickles-jeweler -s http://gems.github.com"
end
