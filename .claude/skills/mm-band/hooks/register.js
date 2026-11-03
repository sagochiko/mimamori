// mm-band: one line above the prompt that keeps the race in view.
//   残り 5日8時間 · M1 主役が通り母に届く(あと1日12時間) · dev 見逃し 13% 誤判定 0% · 作者待ち 2
// It reads CONDITIONS.md, eval/results.jsonl, and docs/human-queue.md from the repository,
// the same files the session hook hands to Claude, so the author and Claude see the same state.

let state = { deadline: '', milestone: '', due: '', evalLine: '', waiting: 0 }

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

  const queue = await readText($, 'docs/human-queue.md')
  state.waiting = (queue.match(/^- \[ \]/gm) || []).length
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
