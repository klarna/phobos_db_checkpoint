require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
end

require 'bundler/setup'

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'phobos_db_checkpoint'

require 'fileutils'
require 'pry-byebug'
require 'database_cleaner'
require 'pg'

require 'coveralls'

# save to CircleCI's artifacts directory if we're on CircleCI
if ENV['CIRCLE_ARTIFACTS']
  dir = File.join(ENV['CIRCLE_ARTIFACTS'], "coverage")
  SimpleCov.coverage_dir(dir)
end

SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new([
  SimpleCov::Formatter::HTMLFormatter,
  Coveralls::SimpleCov::Formatter
])

ENV['RAILS_ENV'] = ENV['RACK_ENV'] = 'test'
SPEC_DB_DIR = 'spec/setup'

def setup_test_env
  PhobosDBCheckpoint.db_config_path = 'spec/database.test.yml'
  PhobosDBCheckpoint.db_dir = SPEC_DB_DIR
  PhobosDBCheckpoint.migration_path = File.join(SPEC_DB_DIR, 'migrate')
end

PhobosDBCheckpoint.load_tasks
setup_test_env

begin
  Rake.application['db:environment:set'].invoke
  Rake.application['db:drop'].invoke
rescue ActiveRecord::NoDatabaseError
end

FileUtils.rm_rf(SPEC_DB_DIR)
result = %x{./bin/phobos_db_checkpoint copy-migrations --destination #{PhobosDBCheckpoint.migration_path} --config #{PhobosDBCheckpoint.db_config_path}}
raise "Copy migrations command failed\n#{result}" unless $?.success?

Rake.application['db:create'].invoke
Rake.application['db:migrate'].invoke

Phobos.silence_log = true
Phobos.configure('spec/phobos.test.yml')
PhobosDBCheckpoint.configure
DatabaseCleaner.strategy = :truncation
DatabaseCleaner::ActiveRecord.config_file_location = PhobosDBCheckpoint.db_config

RSpec.configure do |config|
  config.before(:context, standalone: true) do
    ActiveRecord::Base.connection.disconnect!
  end

  config.after(:context, standalone: true) do
    PhobosDBCheckpoint.configure
  end

  # rspec-expectations config goes here. You can use an alternate
  # assertion/expectation library such as wrong or the stdlib/minitest
  # assertions if you prefer.
  config.expect_with :rspec do |expectations|
    # This option will default to `true` in RSpec 4. It makes the `description`
    # and `failure_message` of custom matchers include text for helper methods
    # defined using `chain`, e.g.:
    #     be_bigger_than(2).and_smaller_than(4).description
    #     # => "be bigger than 2 and smaller than 4"
    # ...rather than:
    #     # => "be bigger than 2"
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  # rspec-mocks config goes here. You can use an alternate test double
  # library (such as bogus or mocha) by changing the `mock_with` option here.
  config.mock_with :rspec do |mocks|
    # Prevents you from mocking or stubbing a method that does not exist on
    # a real object. This is generally recommended, and will default to
    # `true` in RSpec 4.
    mocks.verify_partial_doubles = true
  end

  config.run_all_when_everything_filtered = true

  # Allows RSpec to persist some state between runs in order to support
  # the `--only-failures` and `--next-failure` CLI options. We recommend
  # you configure your source control system to ignore this file.
  config.example_status_persistence_file_path = 'spec/examples.txt'

  # Limits the available syntax to the non-monkey patched syntax that is
  # recommended. For more details, see:
  #   - http://myronmars.to/n/dev-blog/2012/06/rspecs-new-expectation-syntax
  #   - http://www.teaisaweso.me/blog/2013/05/27/rspecs-new-message-expectation-syntax/
  #   - http://myronmars.to/n/dev-blog/2014/05/notable-changes-in-rspec-3#new__config_option_to_disable_rspeccore_monkey_patching
  config.disable_monkey_patching!

  # This setting enables warnings. It's recommended, but in some cases may
  # be too noisy due to issues in dependencies.
  config.warnings = false

  config.expose_dsl_globally = true

  # Many RSpec users commonly either run the entire suite or an individual
  # file, and it's useful to allow more verbose output when running an
  # individual spec file.
  if config.files_to_run.one?
    # Use the documentation formatter for detailed output,
    # unless a formatter has already been configured
    # (e.g. via a command-line flag).
    config.default_formatter = 'doc'
  end

  config.before(:each) do
    setup_test_env
  end

  config.before(:each, type: :db) do
    DatabaseCleaner.start
  end

  config.after(:each, type: :db) do
    DatabaseCleaner.clean
  end

  # Print the 10 slowest examples and example groups at the
  # end of the spec run, to help surface which specs are running
  # particularly slow.
  config.profile_examples = false

  # Run specs in random order to surface order dependencies. If you find an
  # order dependency and want to debug it, you can fix the order by providing
  # the seed, which is printed after each run.
  #     --seed 1234
  config.order = :random

  # Seed global randomization in this process using the `--seed` CLI option.
  # Setting this allows you to use `--seed` to deterministically reproduce
  # test failures related to randomization by passing the same `--seed` value
  # as the one that triggered the failure.
  Kernel.srand config.seed
end
