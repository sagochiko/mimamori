// One Cron Trigger ("*/5 * * * *") drives every scheduled job, because the Free plan allows only
// 5 Cron Triggers per account. Each job says when it is due; dueJobs() picks them from the tick time.
// To add a job (Gmail polling in task 7), put it in JOBS. Jobs run one after another in JOBS order
// and share one budget of outside calls, so notices go before the cleanup that takes what is left.

import { ExternalBudget } from "./budget";
import { sendFirstNotices, watchUnanswered } from "./cases";
import { purgeExpired, purgeExpiredSessions } from "./retention";

const TICK_MINUTES = 5;
const JST_OFFSET_MS = 9 * 3600_000;

/** Jobs in one tick share one budget of outside calls (see src/budget.ts). */
type Run = (env: Env, now: number, budget: ExternalBudget) => Promise<void>;

export type Job =
  | { name: string; everyMinutes: number; run: Run }
  // dailyAtJst is "HH:MM" on a 5-minute boundary.
  | { name: string; dailyAtJst: string; run: Run };

export const JOBS: Job[] = [
  // First notices the family never got (the queue gave up while APNs failed). Before the watch, so a
  // case's first notice goes out before its reminder.
  { name: "case-first-notice", everyMinutes: 5, run: sendFirstNotices },
  // Cases nobody accepted within 30 minutes. Before the cleanup, so notices are never starved by it.
  { name: "case-watch", everyMinutes: 5, run: watchUnanswered },
  // 04:00 JST, when the family is least likely to be using the app.
  { name: "retention", dailyAtJst: "04:00", run: purgeExpired },
  // Agent sessions of old cases, a few at a time, so a backlog finishes over the following ticks.
  { name: "retention-sessions", everyMinutes: 5, run: purgeExpiredSessions },
];

/** Minutes since midnight in JST, rounded down to the tick. Ticks can arrive a little late. */
function jstTickMinute(scheduledTime: number): number {
  const minutes = Math.floor((scheduledTime + JST_OFFSET_MS) / 60_000) % (24 * 60);
  return minutes - (minutes % TICK_MINUTES);
}

export function dueJobs<T extends Job>(scheduledTime: number, jobs: readonly T[]): T[] {
  const minute = jstTickMinute(scheduledTime);
  return jobs.filter((job) => {
    if ("everyMinutes" in job) return minute % job.everyMinutes === 0;
    const [h, m] = job.dailyAtJst.split(":").map(Number);
    return minute === (h ?? 0) * 60 + (m ?? 0);
  });
}

/**
 * Runs each due job in JOBS order, one after another, so an earlier job gets the shared budget first.
 * One job failing does not stop the others.
 */
export async function runScheduled(env: Env, scheduledTime: number, jobs: readonly Job[] = JOBS): Promise<void> {
  const budget = new ExternalBudget();
  for (const job of dueJobs(scheduledTime, jobs)) {
    try {
      await job.run(env, scheduledTime, budget);
    } catch (error) {
      const reason = error instanceof Error ? error.name : typeof error;
      console.error("cron job failed", job.name, reason);
    }
  }
}
