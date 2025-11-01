require 'time'

module AppEncoding
  class Rfc3339Nano
    def format(when_time)
      when_time.utc.iso8601(9)
    end

    def parse(when_string)
      Time.iso8601(when_string)
    end

    def now
      Time.now.utc
    end
  end
end
