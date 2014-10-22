require 'chore/publisher'
require 'beaneater'

module Chore
  module Queues
    module Beanstalkd
      
      # Beanstalk Publisher, for writing messages to Beanstalk from Chore
      class Publisher < Chore::Publisher
        @@reset_next = true

        def initialize(opts={})
          super
          @tubes = {}
        end

        # Takes a given Chore::Job instance +job+, and publishes it by looking up the +tube_name+.
        def publish(tube_name,job)
          tube = self.tube(tube_name)
          tube.put(encode_job(job))
        end

        # Sets a flag that instructs the publisher to reset the connection the next time it's used
        def self.reset_connection!
          @@reset_next = true
        end

        # Access to the configured Beanstalkd connection object
        def beanstalk
          @beanstalk ||= Beaneater::Pool.new(Chore.config.beanstalk_hosts)
        end

        # Retrieves the Beanstalk tube with the given +name+. The method will cache the results to prevent round trips on subsequent calls
        # If <tt>reset_connection!</tt> has been called, this will result in the connection being re-initialized,
        # as well as clear any cached results from prior calls
        def tube(name)
          if @@reset_next && @beanstalk
            @beanstalk.close
            @beanstalk = nil
            @@reset_next = false
            @tubes = {}
          end
          @tubes[name] ||= beanstalk.tubes[name]
        end
      end
    end
  end
end
