require 'json'
require 'rack'
require 'sinatra/base'

require 'phobos_db_checkpoint/middleware/logger'
require 'phobos_db_checkpoint/middleware/database'

module PhobosDBCheckpoint
  class EventsAPI < Sinatra::Base
    VERSION = :v1
    set :logging, nil

    not_found do
      content_type :json
      { error: true, message: 'not found' }.to_json
    end

    error ActiveRecord::RecordNotFound do
      content_type :json
      status 404
      { error: true, message: 'event not found' }.to_json
    end

    error do
      content_type :json
      error = env['sinatra.error']
      { error: true, message: error.message }.to_json
    end

    get '/ping' do
      'PONG'
    end

    get "/#{VERSION}/events/:id" do
      content_type :json
      PhobosDBCheckpoint::Event
        .find(params['id'])
        .to_json
    end

    post "/#{VERSION}/events/:id/retry" do
      content_type :json
      event = PhobosDBCheckpoint::Event.find(params['id'])
      handler_name = event.configured_handler

      unless handler_name
        status 422
        return { error: true, message: 'no handler configured for this event' }.to_json
      end

      handler_class = handler_name.constantize
      metadata = { listener_id: 'events_api/retry', group_id: event.group_id, topic: event.topic, retry_count: 0 }
      event_action = handler_class.new.consume(event.payload, metadata)

      { acknowledged: event_action.is_a?(PhobosDBCheckpoint::Ack) }.to_json
    end

    get "/#{VERSION}/events" do
      content_type :json
      limit = (params['limit'] || 20).to_i
      offset = (params['offset'] || 0).to_i

      query = PhobosDBCheckpoint::Event
      query = query.where(topic: params['topic']) if params['topic']
      query = query.where(group_id: params['group_id']) if params['group_id']
      query = query.where(entity_id: params['entity_id']) if params['entity_id']
      query = query.where(event_type: params['event_type']) if params['event_type']

      query
        .order(event_time: :desc)
        .limit(limit)
        .offset(offset)
        .to_json
    end
  end
end