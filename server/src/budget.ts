// Workers Free allows 50 external subrequests per invocation (D1 and R2 do not count toward it;
// developers.cloudflare.com/workers/platform/limits/#subrequests). Code that calls outside services
// in a loop takes a ticket per call, and what is left over waits for the next request or tick.
//
// D1 has a limit of its own: its limits page gives Free 50 queries per Worker invocation
// (developers.cloudflare.com/d1/platform/limits/), while the Workers limits page counts D1 among the
// 1,000 calls to Cloudflare services (both read on 2026-11-06). One tick of 60 queries ran without an
// error on 2026-11-07 (#178), but the tick keeps to the 50 anyway. runScheduled counts every D1 call
// the jobs make (countD1), and each job looks at d1Remaining before it starts one more item, so an item
// is never cut off halfway (a claim taken, its notice not sent) and what does not fit waits for the next
// tick. Outside the tick nothing counts, and d1Remaining is unlimited.

export const EXTERNAL_CALLS_PER_INVOCATION = 40;
/**
 * What the tick's jobs may plan for. Ten below the 50: a job's estimate leaves out the UPDATE that
 * forgets a device APNs refused (src/push.ts, at most one per device of the item being sent), and the
 * daily cleanup (src/retention.ts, two calls) runs without looking.
 */
export const D1_CALLS_PER_TICK = 40;

export class ExternalBudget {
  private left: number;
  private d1Left: number;

  constructor(limit = EXTERNAL_CALLS_PER_INVOCATION, d1Limit = Number.POSITIVE_INFINITY) {
    this.left = limit;
    this.d1Left = d1Limit;
  }

  get remaining(): number {
    return this.left;
  }

  /** D1 calls the invocation can still make; only the tick sets a limit. Can go below 0, never stops a call. */
  get d1Remaining(): number {
    return this.d1Left;
  }

  /** True and one ticket fewer, or false when the invocation has used its share. */
  take(): boolean {
    return this.takeMany(1);
  }

  /** All n tickets or none, for work that must not be done halfway (one notice to a whole family). */
  takeMany(n: number): boolean {
    if (n > this.left) return false;
    this.left -= n;
    return true;
  }

  /** Called by countD1 for each D1 call made. */
  spendD1(n = 1): void {
    this.d1Left -= n;
  }
}

/**
 * The same database, with every call counted on the budget. A statement is counted when it is
 * prepared (every statement in this code runs once, right after), and a batch is one call however
 * many statements it carries, so it gives back the ones its statements were counted for.
 */
export function countD1(db: D1Database, budget: ExternalBudget): D1Database {
  return {
    prepare: (query: string) => {
      budget.spendD1();
      return db.prepare(query);
    },
    batch: <T = unknown>(statements: D1PreparedStatement[]) => {
      budget.spendD1(1 - statements.length);
      return db.batch<T>(statements);
    },
    exec: (query: string) => {
      budget.spendD1();
      return db.exec(query);
    },
    withSession: db.withSession.bind(db),
    dump: db.dump.bind(db),
  } as D1Database;
}
