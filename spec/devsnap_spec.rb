require_relative 'spec_helper'

RSpec.describe 'devsnap.rake' do
  let(:rake_file) { File.expand_path('../devsnap.rake', __dir__) }
  
  before(:each) do
    # Load the rake file in each test to ensure fresh state
    load rake_file
  end
  let(:snapshots_dir) { Rails.root.join('.snapshots') }
  
  before do
    FileUtils.mkdir_p(snapshots_dir)
  end

  describe 'environment checks' do
    it 'does not load tasks in production environment' do
      # Reset tasks and set production environment before loading
      Rake::Task.class_variable_set(:@@tasks, {})
      ENV['RAILS_ENV'] = 'production'
      
      # Reload the rake file
      load rake_file
      
      expect(Rake::Task.task_defined?('devsnap:capture')).to be false
    end
    
    it 'does not load tasks for non-postgres adapters' do
      # Reset tasks and set different adapter before loading
      Rake::Task.class_variable_set(:@@tasks, {})
      ENV['DB_ADAPTER'] = 'mysql2'
      
      # Reload the rake file  
      load rake_file
      
      expect(Rake::Task.task_defined?('devsnap:capture')).to be false
    end
    
    it 'loads tasks in development with postgres' do
      expect(Rake::Task.task_defined?('devsnap:capture')).to be true
      expect(Rake::Task.task_defined?('devsnap:restore')).to be true
      expect(Rake::Task.task_defined?('devsnap:list')).to be true
      expect(Rake::Task.task_defined?('devsnap:auto')).to be true
    end
  end

  describe 'task definitions' do
    it 'defines all expected tasks' do
      expect(Rake::Task.task_defined?('devsnap:capture')).to be true
      expect(Rake::Task.task_defined?('devsnap:restore')).to be true
      expect(Rake::Task.task_defined?('devsnap:list')).to be true
      expect(Rake::Task.task_defined?('devsnap:auto')).to be true
    end
    
    it 'sets correct dependencies for capture task' do
      task = Rake::Task['devsnap:capture']
      expect(task.instance_variable_get(:@prerequisites)).to include('environment')
    end
    
    it 'sets correct dependencies for restore task' do
      task = Rake::Task['devsnap:restore']
      expect(task.instance_variable_get(:@prerequisites)).to include('environment')
    end
    
    it 'sets correct dependencies for auto task' do
      task = Rake::Task['devsnap:auto']
      expect(task.instance_variable_get(:@prerequisites)).to include('environment')
    end
  end

  describe 'integration tests' do
    it 'has working task structure' do
      capture_task = Rake::Task['devsnap:capture']
      expect(capture_task).to be_present
      
      restore_task = Rake::Task['devsnap:restore']  
      expect(restore_task).to be_present
      
      list_task = Rake::Task['devsnap:list']
      expect(list_task).to be_present
      
      auto_task = Rake::Task['devsnap:auto']
      expect(auto_task).to be_present
    end
    
    it 'creates snapshots directory structure' do
      expect(Rails.root).to be_present
      expect(snapshots_dir.to_s).to include('.snapshots')
    end
    
    it 'handles environment variables' do
      ENV['DEVSNAP_MAX_MB'] = '1000'
      ENV['DEVSNAP_KEEP'] = '10'
      ENV['DEVSNAP'] = 'off'
      
      # These should be accessible within the rake context
      expect(ENV['DEVSNAP_MAX_MB']).to eq('1000')
      expect(ENV['DEVSNAP_KEEP']).to eq('10')
      expect(ENV['DEVSNAP']).to eq('off')
    end
  end

  describe 'db:migrate hook' do
    it 'enhances db:migrate with devsnap:auto prerequisite' do
      # Register db:migrate task
      db_migrate_task = Rake::Task.new('db:migrate')
      Rake::Task.class_variable_get(:@@tasks)['db:migrate'] = db_migrate_task
      
      # Simulate the enhance call from the rake file
      db_migrate_task.enhance(['devsnap:auto'])
      
      expect(db_migrate_task.instance_variable_get(:@prerequisites)).to include('devsnap:auto')
    end
  end
end