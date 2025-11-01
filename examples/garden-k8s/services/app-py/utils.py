def get_sub_json(data, label):
    query = f'"{label}":'

    body_start = data.find(query) + len(query)
    if body_start == -1 + len(query):
        raise ValueError("missing body in response")

    brace_count = 0
    in_body = False
    body_end = -1

    for i in range(body_start, len(data)):
        char = data[i]
        if char == '{':
            in_body = True
            brace_count += 1
        elif char == '}':
            brace_count -= 1
            if in_body and brace_count == 0:
                body_end = i + 1
                break

    if body_end == -1:
        raise ValueError("failed to extract body from response")

    return data[body_start:body_end]
