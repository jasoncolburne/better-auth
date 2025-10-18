import { ITimestamper } from 'better-auth-ts'

export class Rfc3339Nano implements ITimestamper {
  format(when: Date): string {
    const isoString = when.toISOString()
    return isoString.replace('Z', '000000Z')
  }

  parse(when: string | Date): Date {
    if (typeof when === 'string') {
      // Truncate nanoseconds to milliseconds for JavaScript Date compatibility
      // Match timestamps with 9 or more fractional digits before Z
      when = when.replace(/\.(\d{3})\d+Z/, '.$1Z')
    }

    return new Date(when)
  }

  now(): Date {
    return new Date()
  }
}
