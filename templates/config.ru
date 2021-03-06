# frozen_string_literal: true

require 'bundler/setup'
require 'phobos_db_checkpoint'
require 'phobos_db_checkpoint/events_api'
require_relative './phobos_boot.rb'

logger_config = {
  # config: 'config/phobos.yml'
  # log_file: 'log/api.log'
}

use PhobosDBCheckpoint::Middleware::Logger, logger_config
use PhobosDBCheckpoint::Middleware::Database
run PhobosDBCheckpoint::EventsAPI
