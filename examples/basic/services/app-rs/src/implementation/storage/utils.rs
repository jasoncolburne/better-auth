/// Extracts a named JSON object from within a JSON string without fully parsing it.
/// This preserves the exact formatting of the JSON for signature verification.
///
/// # Arguments
/// * `data` - The JSON string containing the field
/// * `label` - The name of the field to extract (e.g., "body" or "payload")
///
/// # Returns
/// The extracted JSON object as a string
///
/// # Errors
/// Returns an error if:
/// - The label is not found in the data
/// - The JSON object cannot be fully extracted (malformed JSON)
pub fn get_sub_json(data: &str, label: &str) -> Result<String, String> {
    let query = format!("\"{}\":", label);

    let body_start = data
        .find(&query)
        .ok_or_else(|| format!("missing {} in response", label))?
        + query.len();

    let mut brace_count = 0;
    let mut in_body = false;
    let mut body_end = None;

    for (i, ch) in data[body_start..].chars().enumerate() {
        let idx = body_start + i;
        match ch {
            '{' => {
                in_body = true;
                brace_count += 1;
            }
            '}' => {
                brace_count -= 1;
                if in_body && brace_count == 0 {
                    body_end = Some(idx + 1);
                    break;
                }
            }
            _ => {}
        }
    }

    let body_end = body_end.ok_or_else(|| format!("failed to extract {} from response", label))?;
    Ok(data[body_start..body_end].to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_sub_json_simple() {
        let json = r#"{"outer":{"body":{"key":"value"}}}"#;
        let result = get_sub_json(json, "body").unwrap();
        assert_eq!(result, r#"{"key":"value"}"#);
    }

    #[test]
    fn test_get_sub_json_nested() {
        let json = r#"{"outer":{"body":{"nested":{"inner":"value"}}}}"#;
        let result = get_sub_json(json, "body").unwrap();
        assert_eq!(result, r#"{"nested":{"inner":"value"}}"#);
    }

    #[test]
    fn test_get_sub_json_with_whitespace() {
        let json = r#"{"outer": {"body": {"key": "value"} }}"#;
        let result = get_sub_json(json, "body").unwrap();
        assert_eq!(result, r#"{"key": "value"}"#);
    }

    #[test]
    fn test_get_sub_json_missing_label() {
        let json = r#"{"outer":{"other":{"key":"value"}}}"#;
        let result = get_sub_json(json, "body");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("missing body"));
    }

    #[test]
    fn test_get_sub_json_malformed() {
        let json = r#"{"body":{"key":"value""#;
        let result = get_sub_json(json, "body");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("failed to extract"));
    }
}
