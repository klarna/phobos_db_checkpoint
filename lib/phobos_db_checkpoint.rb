require 'yaml'
require 'digest'
require 'active_record'
require 'phobos'

require 'phobos_db_checkpoint/event_helper'
require 'phobos_db_checkpoint/version'
require 'phobos_db_checkpoint/errors'
require 'phobos_db_checkpoint/event_actions'
require 'phobos_db_checkpoint/event'
require 'phobos_db_checkpoint/failure'
require 'phobos_db_checkpoint/handler'
require 'phobos_db_checkpoint/actions/retry_failure'

module PhobosDBCheckpoint
  DEFAULT_DB_DIR = 'db'.freeze
  DEFAULT_MIGRATION_PATH = File.join(DEFAULT_DB_DIR, 'migrate').freeze
  DEFAULT_DB_CONFIG_PATH = 'config/database.yml'.freeze
  DEFAULT_POOL_SIZE = 5.freeze

  class << self
    attr_reader :db_config
    attr_accessor :db_config_path, :db_dir, :migration_path, :verbose

    # :nodoc:
    # ActiveRecord hook
    def table_name_prefix
      :phobos_db_checkpoint_
    end

    def configure(pool_size: nil)
      @verbose && puts("PhobosDBCheckpoint#configure - pool_size = #{pool_size}")
      load_db_config(pool_size: pool_size)
      at_exit { PhobosDBCheckpoint.close_db_connection }
      PhobosDBCheckpoint.establish_db_connection
    end

    def env
      ENV['RAILS_ENV'] ||= ENV['RACK_ENV'] ||= 'development'
    end

    def load_db_config(pool_size: nil)
      @verbose && puts("PhobosDBCheckpoint#load_db_config - pool_size = #{pool_size}")

      @db_config_path ||= ENV['DB_CONFIG'] || DEFAULT_DB_CONFIG_PATH
      @verbose && puts("PhobosDBCheckpoint#load_db_config - db_config_path = #{@db_config_path}, env = #{env}")

      configs = YAML.load(ERB.new(File.read(File.expand_path(@db_config_path))).result)
      @db_config = configs[env]

      if pool_size.nil? && Phobos.config
        pool_size = number_of_concurrent_listeners + DEFAULT_POOL_SIZE
      end

      @verbose && puts("PhobosDBCheckpoint#load_db_config - Pool size = #{pool_size || DEFAULT_POOL_SIZE}")
      @db_config.merge!('pool' => pool_size || DEFAULT_POOL_SIZE)
    end

    def establish_db_connection
      @verbose && puts("PhobosDBCheckpoint#establish_db_connection")
      ActiveRecord::Base.establish_connection(db_config)
    end

    def close_db_connection
      @verbose && puts("PhobosDBCheckpoint#close_db_connection")
      ActiveRecord::Base.connection_pool.disconnect!
    rescue ActiveRecord::ConnectionNotEstablished
    end

    def load_tasks
      @db_dir ||= DEFAULT_DB_DIR
      @migration_path ||= DEFAULT_MIGRATION_PATH
      @verbose && puts("PhobosDBCheckpoint#load_tasks - db_dir = #{@db_dir}, migration_path = #{@migration_path}")
      ActiveRecord::Tasks::DatabaseTasks.send(:define_method, :db_dir) { PhobosDBCheckpoint.db_dir }
      ActiveRecord::Tasks::DatabaseTasks.send(:define_method, :migrations_paths) { [PhobosDBCheckpoint.migration_path] }
      ActiveRecord::Tasks::DatabaseTasks.send(:define_method, :env) { PhobosDBCheckpoint.env }
      require 'phobos_db_checkpoint/tasks'
    end

    def number_of_concurrent_listeners
      Phobos.config.listeners.map { |listener| listener.max_concurrency || 1 }.inject(&:+)
    end
  end
end
