import { ITimestamper } from 'better-auth-ts'

export class Rfc3339Nano implements ITimestamper {
  format(when: Date): string {
    // Use standard RFC3339 format with millisecond precision (3 digits)
    return when.toISOString()
  }

  parse(when: string | Date): Date {
    if (typeof when === 'string') {
      // Truncate any extra precision beyond milliseconds for JavaScript Date compatibility
      // Match timestamps with more than 3 fractional digits before Z
      when = when.replace(/\.(\d{3})\d+Z/, '.$1Z')
    }

    return new Date(when)
  }

  now(): Date {
    return new Date()
  }
}
