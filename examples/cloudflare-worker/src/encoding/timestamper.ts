import type { ITimestamper } from 'better-auth-ts';

export class Rfc3339 implements ITimestamper {
  format(when: Date): string {
    return when.toISOString();
  }

  parse(when: string | Date): Date {
    let dateStr: string;
    if (when instanceof Date) {
      dateStr = when.toISOString();
    } else {
      dateStr = when;
    }
    // Truncate sub-ms precision
    const truncated = dateStr.replace(/\.(\d{3})\d+Z$/, '.$1Z');
    return new Date(truncated);
  }

  now(): Date {
    return new Date();
  }
}
