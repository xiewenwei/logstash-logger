require 'poseidon'

module LogStashLogger
  module Device
    class Kafka < Connectable

      DEFAULT_HOST = 'localhost'
      DEFAULT_PORT = 9092
      DEFAULT_TOPIC = 'logstash'
      DEFAULT_PRODUCER = 'logstash-logger'
      DEFAULT_BACKOFF = 1

      attr_accessor :hosts, :topic, :producer, :backoff

      def initialize(opts)
        super
        host = opts[:host] || DEFAULT_HOST
        port = opts[:port] || DEFAULT_PORT
        @hosts = opts[:hosts] || host.split(',').map { |h| "#{h}:#{port}" }
        @topic = opts[:path] || DEFAULT_TOPIC
        @producer = opts[:producer] || DEFAULT_PRODUCER
        @backoff = opts[:backoff] || DEFAULT_BACKOFF
        @buffer_group = @topic
      end

      def connect
        @io = ::Poseidon::Producer.new(@hosts, @producer)
      end

      def reconnect
        @io.close
        connect
      end

      def with_connection
        connect unless @io
        yield
      rescue ::Poseidon::Errors::ChecksumError, Poseidon::Errors::UnableToFetchMetadata => e
        log_error(e)
        log_warning("reconnect/retry")
        sleep backoff if backoff
        reconnect
        retry
      rescue => e
        log_error(e)
        log_warning("giving up")
        @io = nil
      end

      def write_batch(messages, topic)
        with_connection do
          @io.send_messages messages.map { |message| Poseidon::MessageToSend.new(topic, message) }
        end
      end

      def close
        buffer_flush(final: true)
        @io && @io.close
      rescue => e
        log_error(e)
      ensure
        @io = nil
      end
    end
  end
end
