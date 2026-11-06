---
name: mm-deploy
description: Deploys mimamori's Cloudflare Workers backend, first time and later - preflight, deploy, remote D1 migrations, a smoke check, logs, then pointing the iOS app at the deployed host. Remote steps run without waiting for the author; only deleting asks. Use for "デプロイして", "裏側を出して", "/mm-deploy".
---

# Deploy the Workers backend

Since 2026-11-04 the remote steps here (deploy, rollback, `secret list`, remote D1 migrations) run without waiting for the author: the author decided that during development only deleting and what cannot be undone needs their approval. Before each remote step, still say in one line what it changes. wrangler skips its own confirmation in a non-interactive shell, so `guard-prod.sh` is what keeps the rest with the author: it blocks deleting resources and D1 time-travel restore, and asks before `wrangler secret delete` and before remote SQL with DROP, DELETE, or TRUNCATE. Never reshape a command to avoid a prompt or a block. Never read, write, or print a secret value; the author enters the values (issue #30). Piping a random key straight from `openssl rand` into `wrangler secret put` (as for `TOKEN_ENC_KEY`) is fine.

Run everything from `server/` unless a step says otherwise.

## 0. Before the first deploy

R2 is enabled in the dashboard (issue #28) and the five secrets are registered (issue #30). Without them the first deploy stops.

## 1. Preflight (local)

```sh
npm ci && (cd .. && make verify)
npx wrangler deploy --dry-run
```

The dry run must list `env.JUDGE_QUEUE` (Queue), `env.DB` (D1), `env.PHOTOS` (R2), `env.JOIN_LIMITER` (Rate Limit), and `env.APNS_TOPIC`, then `--dry-run: exiting now.`

## 2. Secrets exist

```sh
npx wrangler secret list
```

It prints names and types only; Cloudflare never returns secret values. Compare with `secrets.required` in `wrangler.jsonc`: `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `ANTHROPIC_API_KEY`, `TOKEN_ENC_KEY`. If a name is missing or the Worker is not found, stop and point the author to issue #30. `wrangler deploy` also refuses to deploy while a required secret is missing and lists the missing names.

## 3. Deploy

On later deploys, run step 4 first when `migrations list` shows unapplied migrations, so new code never meets the old tables. On the first deploy the database does not exist yet, so deploy first.

```sh
npx wrangler deploy
```

First deploy:

- Wrangler creates the D1 database `mimamori`, the R2 bucket, and the queue `mimamori-judge`, and writes their IDs back into `wrangler.jsonc`. Commit that diff on a branch (`chore(server): 最初のデプロイで作った資源の ID を書き戻す`).
- Whether the Rate Limiting binding (`ratelimits`, `JOIN_LIMITER`) works on the Free plan is not confirmed; this deploy shows it. If the deploy fails on it, stop, record it with `/mm-devlog`, and ask the author how to proceed (a paid plan, or another way to limit joins as its own issue). If it deploys, step 5 shows whether it enforces.
- If Wrangler asks for a workers.dev subdomain, the account has none yet. Choose it in Chrome so that the author only confirms: load the Claude in Chrome tools in one ToolSearch call (the `chrome-browser` skill), open `https://dash.cloudflare.com/?to=/:account/workers-and-pages` in a new tab, select Change next to Your subdomain, and type a name. Read only the subdomain field with `find`; the page also lists the account's Workers, which can belong to the author's earlier projects, so do not read the whole page or take screenshots. The name must hold no person's name (it becomes part of the public URL; `mimamori-` and a few random letters is enough). If the sign-in page appears first, click into its password field and ask the author only to sign in. Then ask the author in one line to press the dialog's confirm button, and wait with `run_in_background` until the name resolves: `for i in $(seq 360); do [ -n "$(dig +short <name>.workers.dev)" ] && exit 0; sleep 5; done; exit 1`. Since 2026-11-04 the deploy no longer stops for approval, so it can no longer serve as the wait. A name nobody has claimed does not resolve (checked on 2026-11-04 with `dig` on a random name); that a claimed name resolves before any Worker is on it is not confirmed, so if the loop times out, ask once whether the button was pressed. Then run `npx wrangler deploy` again. If it still asks for a subdomain, the button was not pressed yet; ask once more.
- Until step 4 has run, every 5-minute Cron tick logs `cron job failed retention-sessions` in the tail: that job queries the `cases` table (`src/retention.ts`), which does not exist before the migration, and `runScheduled` in `src/cron.ts` catches the error and logs it instead of failing. If the daily `retention` run (`dailyAtJst` in `src/cron.ts`) falls in between, `cron job failed retention` appears once for the same reason. Both stop after the migration; if they do not, look at the job.
- Take the `https://mimamori.<subdomain>.workers.dev` URL from the output. `HOST` below is that URL without `https://`. A new workers.dev subdomain can answer 523 for about a minute; wait and retry.

## 4. Remote D1 migrations

```sh
npx wrangler d1 migrations list mimamori --remote
npx wrangler d1 migrations apply mimamori --remote
```

`apply` captures a backup, and a migration that fails is rolled back while the earlier ones stay (`npx wrangler d1 migrations apply --help`).

## 5. Smoke check

None of these requests writes to D1. The join loop blocks joins from this network address for about a minute, including the author's iPhone on the same Wi-Fi.

```sh
HOST=mimamori.<subdomain>.workers.dev
curl -sS -w '\n%{http_code}\n' "https://$HOST/"
curl -sS -w '\n%{http_code}\n' -X POST -H 'Authorization: Bearer smoke-not-a-key' "https://$HOST/invites"
curl -sS -w '\n%{http_code}\n' "https://$HOST/.well-known/apple-app-site-association"
for i in 1 2 3 4 5 6 7 8; do curl -sS -o /dev/null -w '%{http_code} ' -X POST \
  -H 'Content-Type: application/json' -d '{"role":"family","display_name":"smoke"}' \
  "https://$HOST/invites/x/join"; done; echo
```

| Request | Expected | What it shows |
|---|---|---|
| `GET /` | `{"error":"not_found"}` 404 | The Worker answers |
| `POST /invites` with an unknown key | `{"error":"device_key_invalid"}` 401 | D1 has the `members` table. 500 means the migrations are missing |
| `/.well-known/apple-app-site-association` | 404 until task 5 serves it | See step 7 |
| 8 joins with a malformed code | `404` five times, then `429` | The D1 count (`join_attempts`, #67) enforces it, so the sixth is `429` from any location. All 404 means migration `0009` or the code is missing; 500 often means the `join_attempts` table is missing |

These are the answers `wrangler dev` gives locally. Paste the output in the report.

## 6. Logs

Start this with `run_in_background` while sending the smoke requests or using the app, and stop it afterwards. `--status error` shows only failed invocations.

```sh
npx wrangler tail mimamori --format pretty
```

No family token, device key, or message text may appear (`.claude/rules/server.md`). If one does, stop and fix the log line before anyone uses the app.

## 7. Point the app at the host

Needed after the first deploy, and whenever the host changes. From the repo root, on a branch:

1. In `ios/Config/Shared.xcconfig`, set `MIMAMORI_API_HOST = <HOST>` (host only, no scheme or path) and remove the PLACEHOLDER comment. The `messagefilter:` associated domain of the app and of MessageFilter reads `$(MIMAMORI_API_HOST)` in `ios/project.yml`, so this one line moves both.
2. Regenerate, rebuild, and check the values in the build:

```sh
/opt/homebrew/bin/xcodegen generate --spec ios/project.yml --quiet
DD=<scratchpad>/DerivedData-host
xcodebuild -project ios/Mimamori.xcodeproj -scheme Mimamori -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DD" -quiet build
/usr/libexec/PlistBuddy -c 'Print :MimamoriAPIBaseURL' "$DD/Build/Products/Debug-iphonesimulator/Mimamori.app/Info.plist"
I="$DD/Build/Intermediates.noindex/Mimamori.build/Debug-iphonesimulator"
plutil -p "$I/Mimamori.build/Mimamori.app-Simulated.xcent" | grep messagefilter
plutil -p "$I/MessageFilter.build/MessageFilter.appex-Simulated.xcent" | grep messagefilter
rm -rf "$DD"
```

Expect `https://<HOST>` and `messagefilter:<HOST>` twice. `<scratchpad>` is this session's scratchpad directory.

3. Commit (`chore(ios): API の宛先を本番の Workers にする`) and open a PR. After it merges, `/mm-release` sends a build to TestFlight, to the internal group 「家族」 for the author to check on the iPhone; `/mm-device` is only for a check that needs a Debug launch argument. The changed Associated Domains entry makes the next signed build refresh its profiles.

The SMS extension can only defer to the server once the Worker serves `/.well-known/apple-app-site-association` with a `messagefilter` entry. Apple's "Creating a message filter app extension" says to set the domain up as for Shared Web Credentials, with `messagefilter` in place of `webcredentials`. That belongs to task 5; until then the step 5 request stays 404.

## When a later deploy breaks

`npx wrangler rollback` makes the version before the latest one live again at once. D1 migrations are not undone, and Cloudflare refuses the rollback if that version binds a bucket or queue that no longer exists. Record what happened with `/mm-devlog`.
