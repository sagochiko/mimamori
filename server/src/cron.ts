// One Cron Trigger ("*/5 * * * *") drives every scheduled job, because the Free plan allows only
// 5 Cron Triggers per account. Each job says when it is due; dueJobs() picks them from the tick time.
// To add a job (case watch in task 10, Gmail polling in task 7), append it to JOBS.

import { purgeExpired } from "./retention";

const TICK_MINUTES = 5;
const JST_OFFSET_MS = 9 * 3600_000;

export type Job =
  | { name: string; everyMinutes: number; run: (env: Env, now: number) => Promise<void> }
  // dailyAtJst is "HH:MM" on a 5-minute boundary.
  | { name: string; dailyAtJst: string; run: (env: Env, now: number) => Promise<void> };

export const JOBS: Job[] = [
  // 04:00 JST, when the family is least likely to be using the app.
  { name: "retention", dailyAtJst: "04:00", run: purgeExpired },
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

/** Runs each due job; one job failing does not stop the others. */
export async function runScheduled(env: Env, scheduledTime: number, jobs: readonly Job[] = JOBS): Promise<void> {
  const due = dueJobs(scheduledTime, jobs);
  const results = await Promise.allSettled(due.map((job) => job.run(env, scheduledTime)));
  results.forEach((result, i) => {
    if (result.status === "rejected") {
      const reason = result.reason instanceof Error ? result.reason.name : typeof result.reason;
      console.error("cron job failed", due[i]?.name, reason);
    }
  });
}
