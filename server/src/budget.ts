// Workers Free allows 50 external subrequests per invocation (D1 and R2 do not count toward it;
// developers.cloudflare.com/workers/platform/limits/#subrequests). Code that calls outside services
// in a loop takes a ticket per call, and what is left over waits for the next request or tick.

export const EXTERNAL_CALLS_PER_INVOCATION = 40;

export class ExternalBudget {
  private left: number;

  constructor(limit = EXTERNAL_CALLS_PER_INVOCATION) {
    this.left = limit;
  }

  get remaining(): number {
    return this.left;
  }

  /** True and one ticket fewer, or false when the invocation has used its share. */
  take(): boolean {
    if (this.left <= 0) return false;
    this.left--;
    return true;
  }
}
