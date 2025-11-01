def get_sub_json(value, label)
      query = "\"#{label}\":"
      body_start = value.index(query)
      raise "missing #{label} in response" unless body_start

      body_start += query.length

      brace_count = 0
      in_body = false
      body_end = nil

      value[body_start..-1].each_char.with_index do |char, i|
        idx = body_start + i
        case char
        when '{'
          in_body = true
          brace_count += 1
        when '}'
          brace_count -= 1
          if in_body && brace_count == 0
            body_end = idx + 1
            break
          end
        end
      end

      raise "failed to extract body from response" unless body_end

      value[body_start...body_end]
end