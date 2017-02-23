module PhobosDBCheckpoint
  class Failure < ActiveRecord::Base
    include PhobosDBCheckpoint::EventHelper

    scope :by_checksum, -> (val) { where("metadata->>'checksum' = ?", val) }
    scope :by_topic, -> (val) { where("metadata->>'topic' = ?", val) }
    scope :by_group_id, -> (val) { where("metadata->>'group_id' = ?", val) }

    def self.record(event_payload:, event_metadata:, exception: nil)
      return if exists?(event_metadata[:checksum])

      create do |record|
        record.payload         = event_payload
        record.metadata        = event_metadata
        record.error_class     = exception&.class&.name
        record.error_message   = exception&.message
        record.error_backtrace = exception&.backtrace
      end
    end

    def self.exists?(checksum)
      by_checksum(checksum).exists?
    end

    def payload
      attributes['payload'].deep_symbolize_keys
    end

    def metadata
      attributes['metadata'].deep_symbolize_keys
    end

    def group_id
      metadata[:group_id]
    end

    # Can we delete the failure already at this stage?
    # Since a new error will be created after failing again X times in a row?
    # This would make retrying errors a simple task, one click and forget about it.
    def retry!
      configured_handler
        .new
        .consume(
          payload,
          metadata.merge(retry_count: 0)
        )
    end
  end
end