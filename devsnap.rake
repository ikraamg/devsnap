# devsnap.rake - Automatic DB snapshots for Rails development
# Install: curl -sSL https://raw.githubusercontent.com/ikraamg/devsnap/main/devsnap.rake -o lib/tasks/devsnap.rake && echo ".snapshots/" >> .gitignore

return unless Rails.env.development?
return unless ActiveRecord::Base.connection_db_config.adapter =~ /postgres/i

namespace :devsnap do
  DISABLED = ENV["DEVSNAP"] == "off"
  MAX_SIZE_MB = ENV.fetch("DEVSNAP_MAX_MB", "500").to_i
  MAX_KEEP = ENV.fetch("DEVSNAP_KEEP", "5").to_i
  DIR = Rails.root.join(ENV.fetch("DEVSNAP_DIR", ".snapshots"))
  
  def db_config
    @db_config ||= ActiveRecord::Base.connection_db_config.configuration_hash
  end
  
  def db_size_mb
    result = ActiveRecord::Base.connection.execute(
      "SELECT pg_database_size('#{db_config[:database]}') / 1024 / 1024 AS size"
    ).first
    result["size"].to_i
  end
  
  def snapshot_files
    Dir[DIR.join("*.dump")].sort_by { |f| File.mtime(f) }
  end
  
  def prune_old_snapshots
    files = snapshot_files
    return if files.size <= MAX_KEEP
    
    files[0..-(MAX_KEEP + 1)].each do |file|
      File.delete(file)
      puts "[devsnap] Pruned old snapshot: #{File.basename(file)}"
    end
  end
  
  def pg_env
    { "PGPASSWORD" => db_config[:password].to_s }
  end
  
  def pg_args
    [
      "-h", db_config[:host] || "localhost",
      "-p", (db_config[:port] || 5432).to_s,
      "-U", db_config[:username] || ENV["USER"]
    ]
  end

  desc "Capture current DB state"
  task :capture, [:name] => :environment do |_, args|
    FileUtils.mkdir_p(DIR)
    
    size = db_size_mb
    if size > MAX_SIZE_MB && !ENV["FORCE_SNAP"]
      puts "[devsnap] Skipping - DB is #{size}MB (max: #{MAX_SIZE_MB}MB). Use FORCE_SNAP=1 to override"
      next
    end
    
    prune_old_snapshots
    
    name = args[:name] || Time.now.utc.strftime("%Y%m%d_%H%M%S")
    file = DIR.join("#{name}.dump")
    
    print "[devsnap] Capturing #{size}MB database... "
    success = system(pg_env, "pg_dump", "-Fc", "--no-owner", 
                     *pg_args, db_config[:database], "-f", file.to_s,
                     out: File::NULL, err: File::NULL)
    
    if success
      puts "saved as #{name}.dump"
    else
      puts "FAILED"
      File.delete(file) if File.exist?(file)
    end
  end

  desc "Restore a snapshot" 
  task :restore, [:name] => :environment do |_, args|
    name = args[:name] or abort "Usage: rails devsnap:restore[snapshot_name]"
    file = DIR.join("#{name}.dump")
    abort "[devsnap] Not found: #{file}" unless File.exist?(file)
    
    db = db_config[:database]
    
    print "[devsnap] Restoring #{name}... "
    
    # Terminate connections and recreate DB
    ActiveRecord::Base.connection.disconnect!
    
    system(pg_env, "psql", *pg_args, "-d", "postgres", 
           "-c", "DROP DATABASE IF EXISTS #{db} WITH (FORCE);",
           out: File::NULL, err: File::NULL)
    
    system(pg_env, "createdb", *pg_args, db,
           out: File::NULL, err: File::NULL)
    
    success = system(pg_env, "pg_restore", "--no-owner", "-d", db, 
                     *pg_args, file.to_s,
                     out: File::NULL, err: File::NULL)
    
    puts success ? "done" : "FAILED"
    ActiveRecord::Base.establish_connection
  end

  desc "List snapshots"
  task :list do
    files = snapshot_files.reverse # newest first
    
    if files.empty?
      puts "[devsnap] No snapshots"
    else
      puts "[devsnap] Snapshots (newest first):"
      files.each_with_index do |f, i|
        name = File.basename(f, ".dump")
        size = (File.size(f) / 1024.0 / 1024.0).round(1)
        age = ((Time.now - File.mtime(f)) / 86400).round
        puts "  #{i+1}. #{name} (#{size}MB, #{age}d ago)"
      end
    end
  end

  # Auto-capture before migrations
  task :auto => :environment do
    next if DISABLED
    
    # Check if we have pending migrations
    mc = ActiveRecord::Base.connection.migration_context
    pending = mc.migrations.reject do |m|
      mc.get_all_versions.include?(m.version)
    end
    
    if pending.any?
      Rake::Task["devsnap:capture"].invoke("pre_migrate_#{Time.now.to_i}")
    end
  end
end

# Hook into db:migrate
Rake::Task["db:migrate"].enhance(["devsnap:auto"]) if Rake::Task.task_defined?("db:migrate")