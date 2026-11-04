// mm-band: one line above the prompt that keeps the race in view.
//   残り 5日8時間 · M1 主役が通り母に届く(あと1日12時間) · dev 見逃し 13% 誤判定 0% · 作者待ち 2
// It reads CONDITIONS.md and eval/results.jsonl from the repository, and counts the open "作者:"
// issues with gh, the same things the session hook hands to Claude, so the author and Claude see the
// same state.

let state = { deadline: '', milestone: '', due: '', evalLine: '', waiting: '?' }

// The count of steps waiting for the author is cached for 5 minutes in the file session-context.sh
// also uses (.claude/hooks/lib.sh, author_waiting), as "<epoch seconds> <count>". When gh fails or
// is offline the band shows "?", never a made-up 0.
const WAITING_CACHE = '.claude/state/author-waiting'
const WAITING_TTL_S = 300

async function authorWaiting($) {
  const now = Math.floor(Date.now() / 1000)
  const [at, n] = (await readText($, WAITING_CACHE)).trim().split(/\s+/)
  if (/^\d+$/.test(at) && /^\d+$/.test(n) && now - Number(at) < WAITING_TTL_S) return n
  try {
    const { exitCode, stdout } = await $.process.run(
      ['gh', 'issue', 'list', '--label', 'needs-human', '--state', 'open', '--limit', '200',
        '--json', 'title', '-q', '[.[] | select(.title | startswith("作者:"))] | length'],
      { timeoutMs: 8000 },
    )
    const count = stdout.trim()
    if (exitCode !== 0 || !/^\d+$/.test(count)) return '?'
    try {
      await $.fs.write(WAITING_CACHE, now + ' ' + count + '\n')
    } catch {
      // The count still shows; the next refresh asks gh again.
    }
    return count
  } catch {
    return '?'
  }
}

function frontMatter(text, key) {
  const block = text.split(/^---$/m)[1] || ''
  const m = block.match(new RegExp('^' + key + ':\\s*(.+)$', 'm'))
  return m ? m[1].trim() : ''
}

function untilText(iso, now) {
  const ms = Date.parse(iso) - now
  if (Number.isNaN(ms)) return '?'
  if (ms <= 0) return '過ぎた'
  const h = Math.floor(ms / 3600000)
  const m = Math.floor((ms % 3600000) / 60000)
  return h >= 24 ? Math.floor(h / 24) + '日' + (h % 24) + '時間' : h + '時間' + m + '分'
}

async function readText($, path) {
  try {
    return await $.fs.read(path)
  } catch {
    return ''
  }
}

async function refresh($) {
  const conditions = await readText($, 'CONDITIONS.md')
  state.deadline = frontMatter(conditions, 'deadline')
  state.milestone = frontMatter(conditions, 'milestone')
  state.due = frontMatter(conditions, 'milestone_due')

  const results = (await readText($, 'eval/results.jsonl')).trim().split('\n')
  const lastDev = results.reverse().find((l) => l.includes('"set":"dev"') && l.includes('"mode":"rules+claude"'))
  if (lastDev) {
    try {
      const r = JSON.parse(lastDev)
      state.evalLine = 'dev 見逃し ' + Math.round(r.miss_rate * 100) + '% 誤判定 ' + Math.round(r.false_alarm_rate * 100) + '%'
    } catch {
      state.evalLine = ''
    }
  }

  state.waiting = await authorWaiting($)
  $.ui.invalidate('ui.render')
}

export function register(on) {
  on('session.start', async ($, e, next) => {
    await refresh($)
    $.clock.every(60_000, () => refresh($))
    return next(e)
  })

  // Claude often edits these files mid-turn; pick the change up when the turn ends.
  on('turn.complete', async ($, e, next) => {
    await refresh($)
    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (!state.deadline) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    const now = Date.now()
    const parts = ['残り ' + untilText(state.deadline, now)]
    if (state.milestone) parts.push(state.milestone + '(あと' + untilText(state.due, now) + ')')
    if (state.evalLine) parts.push(state.evalLine)
    parts.push('作者待ち ' + state.waiting)
    return Box({
      flexDirection: 'column',
      children: [Text({ children: [parts.join(' · ')] }), await next(e)],
    })
  })
}
