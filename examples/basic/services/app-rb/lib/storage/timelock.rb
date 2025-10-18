module Storage
  class InMemoryTimeLockStore
    attr_reader :lifetime

    def initialize(lifetime)
      @lifetime = lifetime
      @values = {}
    end

    def reserve(value)
      valid_at = @values[value]

      if valid_at
        now = Time.now

        raise 'value reserved too recently' if now < valid_at
      end

      new_valid_at = Time.now + @lifetime
      @values[value] = new_valid_at

      nil
    end
  end
end
