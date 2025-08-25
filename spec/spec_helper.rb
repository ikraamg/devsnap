require 'rspec'
require 'fileutils'
require 'tmpdir'

# Mock Rails environment for testing
module Rails
  def self.env
    @env ||= MockEnvironment.new
  end
  
  def self.root
    @root ||= Pathname.new(Dir.tmpdir).join("devsnap_test")
  end
  
  class MockEnvironment
    def development?
      ENV['RAILS_ENV'] != 'production'
    end
  end
end

class Pathname
  def join(path)
    Pathname.new(File.join(to_s, path.to_s))
  end
end

# Mock ActiveRecord
module ActiveRecord
  class Base
    def self.connection
      @connection ||= MockConnection.new
    end
    
    def self.connection_db_config
      @connection_db_config ||= MockDbConfig.new
    end
    
    def self.establish_connection
      # Mock method
    end
  end
  
  class MockDbConfig
    def adapter
      ENV['DB_ADAPTER'] || 'postgresql'
    end
    
    def configuration_hash
      {
        adapter: 'postgresql',
        database: 'test_db',
        host: 'localhost',
        port: 5432,
        username: 'test_user',
        password: 'test_pass'
      }
    end
  end
  
  class MockConnection
    def disconnect!
      # Mock method
    end
    
    def execute(sql)
      if sql.include?('pg_database_size')
        [{"size" => "50"}] # 50MB
      else
        []
      end
    end
    
    def migration_context
      @migration_context ||= MockMigrationContext.new
    end
  end
  
  class MockMigrationContext
    def migrations
      @migrations ||= [
        MockMigration.new(20240101000001, "CreateUsers"),
        MockMigration.new(20240101000002, "AddEmailToUsers")
      ]
    end
    
    def get_all_versions
      ENV['PENDING_MIGRATIONS'] == 'true' ? [20240101000001] : [20240101000001, 20240101000002]
    end
  end
  
  class MockMigration
    attr_reader :version, :name
    
    def initialize(version, name)
      @version = version
      @name = name
    end
  end
end

# Mock Rake
module Rake
  class Task
    @@tasks = {}
    
    def self.task_defined?(name)
      @@tasks.key?(name)
    end
    
    def self.[](name)
      @@tasks[name] ||= new(name)
    end
    
    def initialize(name)
      @name = name
      @actions = []
      @prerequisites = []
    end
    
    def enhance(prereqs = [])
      @prerequisites.concat(prereqs)
      self
    end
    
    def invoke(*args)
      @invoked = true
      @args = args
    end
    
    def reenable
      @invoked = false
    end
    
    def invoked?
      @invoked
    end
    
    def args
      @args || []
    end
  end
end

# Mock Rake DSL methods for main context
def namespace(name, &block)
  @current_namespace = name
  block.call if block
ensure
  @current_namespace = nil
end

def desc(description)
  @current_description = description
end

def task(*args, &block)
  # Parse different rake task syntax forms:
  # task :name => dependencies
  # task :name, [:arg1, :arg2] => dependencies  
  # task :name
  
  if args.length == 1
    if args[0].is_a?(Hash)
      # task :name => dependencies
      name = args[0].keys.first
      dependencies = Array(args[0].values.first)
    else
      # task :name
      name = args[0]
      dependencies = []
    end
  elsif args.length == 2
    # task :name, [:args] => dependencies or task :name, dependencies
    name = args[0]
    if args[1].is_a?(Hash)
      dependencies = Array(args[1].values.first)
    else
      dependencies = Array(args[1])
    end
  else
    name = args[0]
    dependencies = []
  end
  
  full_name = @current_namespace ? "#{@current_namespace}:#{name}" : name.to_s
  
  task_obj = Rake::Task.new(full_name)
  task_obj.instance_variable_set(:@actions, [block].compact)
  task_obj.instance_variable_set(:@prerequisites, dependencies.map(&:to_s))
  
  Rake::Task.class_variable_get(:@@tasks)[full_name] = task_obj
  
  task_obj
end

# Add present? method to all objects for Rails-like behavior
class Object
  def present?
    !blank?
  end

  def blank?
    respond_to?(:empty?) ? empty? : !self
  end
end

RSpec.configure do |config|
  config.before(:each) do
    # Reset environment
    ENV['RAILS_ENV'] = 'development'
    ENV['DB_ADAPTER'] = 'postgresql'
    ENV['DEVSNAP'] = nil
    ENV['DEVSNAP_MAX_MB'] = nil
    ENV['DEVSNAP_KEEP'] = nil
    ENV['FORCE_SNAP'] = nil
    ENV['PENDING_MIGRATIONS'] = nil
    
    # Reset Rake tasks
    Rake::Task.class_variable_set(:@@tasks, {})
    
    # Create test directory
    FileUtils.mkdir_p(Rails.root)
    
    # Mock system calls
    allow_any_instance_of(Object).to receive(:system).and_return(true)
  end
  
  config.after(:each) do
    # Cleanup test directory
    FileUtils.rm_rf(Rails.root) if Dir.exist?(Rails.root)
  end
end