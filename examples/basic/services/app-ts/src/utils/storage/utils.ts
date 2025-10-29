
export function getSubJson(value: string, label: string): string {
    // Extract raw body JSON for signature verification
    const query = `"${label}":`

    const bodyStart = value.indexOf(query) + query.length
    let braceCount = 0
    let inBody = false
    let bodyEnd = -1

    for (let i = bodyStart; i < value.length; i++) {
        const char = value[i]
        if (char === '{') {
        inBody = true
        braceCount++
        } else if (char === '}') {
        braceCount--
        if (inBody && braceCount === 0) {
            bodyEnd = i + 1
            break
        }
        }
    }

    if (bodyEnd === -1) {
        throw new Error('failed to extract body from response')
    }

   return value.substring(bodyStart, bodyEnd)
}