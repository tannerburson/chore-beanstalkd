require 'beaneater'
module Chore
  module Queues
    module Beanstalkd
      # Beanstalk Consumer for Chore. Requests messages from Beanstalk and passes them to be worked on. Also controls
      # deleting completed messages within Beanstalk.
      class Consumer < Chore::Consumer
        # Initialize the reset at on class load
        @@reset_at = Time.now

        Chore::CLI.register_option 'beanstalk_hosts', '--beanstalk-hosts', Array, 'Comma separated list of hosts'

        def initialize(tube_name, opts={})
          super(tube_name, opts)
          beanstalk.tubes.watch(tube_name)
        end

        # Sets a flag that instructs the publisher to reset the connection the next time it's used
        def self.reset_connection!
          @@reset_at = Time.now
          @beanstalk.close
          @beanstalk = nil
        end

        # Begins requesting messages from Beanstalk, which will invoke the +&handler+ over each message
        def consume(&handler)
          while running?
            begin
              messages = handle_messages(&handler)
            rescue Beaneater::TimedOutError => e
              next
            rescue => e
              Chore.logger.error { "BeanstalkConsumer#Consume: #{e.inspect} #{e.backtrace * "\n"}" }
            end
          end
        end

        # Rejects the given message from Beanstalk by +id+. Currently a noop
        def reject(id)
          transmit "bury #{id}"
        end

        # Deletes the given message from Beanstalk by +id+
        def complete(id)
          Chore.logger.debug "Completing (deleting): #{id}"
          transmit "delete #{id}"
        end

        private

        # Requests messages from Beanstalk, and invokes the provided +&block+ over each one. Afterwards, the :on_fetch
        # hook will be invoked, per message
        def handle_messages(&block)
          # should get smarter about this. this can do a nice blocking read but we have a stupid infinite loop currently.
          message = tube.reserve(1)
          block.call(message.id, message.tube, message.ttr, message.body, message.stats.reserves)
          Chore.run_hooks_for(:on_fetch, message.id, message.body)
          message
        end

        # Retrieves the Beanstalk tube with the given +name+. The method will cache the results to prevent round trips on
        # subsequent calls. If <tt>reset_connection!</tt> has been called, this will result in the connection being
        # re-initialized, as well as clear any cached results from prior calls
        def tube
          @tube ||= beanstalk.tubes[@queue_name]
        end

        def transmit(command, opts = {})
          @beanstalk.transmit_to_rand(command, opts)
        end

        # Access to the configured Beanstalk connection object
        def beanstalk
          @beanstalk ||= Beaneater::Pool.new(Chore.config.beanstalk_hosts)
        end
      end
    end
  end
end
