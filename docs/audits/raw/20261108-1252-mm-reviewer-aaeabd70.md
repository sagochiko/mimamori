サブエージェントの報告の原文。親のセッションが確かめる前のもの。ホームの道筋だけを ~ に替えた。

ステータス: 承認

対象は PR #290(ブランチ `docs-1108-updates`、先頭 `f34c517`)。`gh pr diff 290` で読み、チェックアウトはしていない。1回目の指摘1〜3は3つとも閉じている。直すべき指摘は無い。

## 指摘

1. 「`make usage` で数え直せる」は少し言い過ぎで、直すかどうかは任せる(確度は中。軽い)
   - 場所は [`docs/submission.md`](docs/submission.md) の「Claude Code」の節(「`make usage` で数え直せる」)と、`video/src/numbers.ts` 36行のコメント。
   - `make usage` は `scripts/usage-report.sh > docs/claude-usage.md` を流すだけだ(`Makefile` 47〜48行)。出てくるのはフックごとの合計で、合わせると356になる。許した記録と通した記録の56件は、`detail` の頭の語で分けないと出てこない。なので、`make usage` を流しても300はそのまま出ない。[`docs/claude-usage.md`](docs/claude-usage.md) にも56件を除くという説明は無い。
   - 審査員に誤った数を見せるものではない。README 2本は「そのファイルのフックの表の合計から56件を除いた数」と内訳まで書いているので、正しく読める。直すなら、提出の下書きの言い方を「`make usage` の表の合計から除いた」に寄せるか、`usage-report.sh` に許した分を除いた行を足すかのどちらか。

## 確かめて問題なかったこと

- 1回目の指摘1(356に止めずに通した記録が混ざる)は閉じた。`~/develop/mimamori/.claude/logs/usage.jsonl` の `kind=="guard"` を、フックの名前と `detail` の頭の語で数え直した。合計は356。内訳のうち許した記録と通した記録は4種類で、合わせて56件、残りは300だった。

  | フック | `detail` の頭 | 件数 |
  |---|---|---:|
  | `guard-holdout` | `cases allowed` | 35 |
  | `guard-holdout` | `final holdout` | 17 |
  | `guard-prod` | `passed: remote` | 3 |
  | `guard-prod` | `passed: SQL` | 1 |

  README 2本の括弧の中の内訳(35、17、4)もこの数と合う。
- 300は、`README.md`、`README.ja.md`、[`docs/submission.md`](docs/submission.md)、`video/src/numbers.ts` の `hookStops` の4か所で揃っている。動画の名札(`video/src/scenes/Closing.tsx` 65行「フックが止めるか作者に確かめた操作」)とも中身が合うようになった。ブランチの中に356と208は残っていなかった(grep で見た)。
- 1回目の指摘2は閉じた。提出の下書き37行は、人ごとに切り替えられるのを2つの知らせのオンとオフだけにし、締めの時刻は家族で1つと書いている。PR #286 の本文と README 2本(英語版121行、日本語版118行)とも合う。
- 1回目の指摘3は閉じた。README 2本は「母が入れた記録はまだ無い」と「No record yet shows that she installed it」になった。Issue #133 の2026年11月8日のコメントの4点目と同じ言い方だ。
- ビルド17の書き方は正しい。Issue #133 のコメントに、App Store Connect の外部グループ「審査員と家族」で「テスト中」と書いてある。PR #288 の本文にも、ビルド17が `demo` の審査員の版で、ビルド18は外部グループ「母だけ」にだけ配ったとある。README の「母の TestFlight の版はまだ審査員と同じ `demo` の版」とも食い違わない。`c9366d0` の `ios/project.yml` の `CURRENT_PROJECT_VERSION` は `"18"` で、README の「PR #288 から18」と合う。
- Gmail の書き方も正しい。#133 の2つ目のコメントが1つ目の「まだ出し直していない」を訂正している。本番の D1 で、作り直した母の家族に `gmail_auth` の行が1件あったという内容だ。README の「母は同じ日に作り直した家族に入り直し、Gmail もつなぎ直した(#133)」は、1つ目のコメントの「見守られる人が入った」と、この訂正の両方に出典がある。家族に1回知らせたのは消えた家族の中でだったと分けて書いてあり、言い過ぎも無い。
- 直しの3コミットで足した行に、時刻の形(`HH:MM` や「〜時」)は無かった(`git diff c9366d0 origin/docs-1108-updates` の追加行を grep で見た)。名前、電話番号、メールアドレス、メールや SMS の本文も無い。`docs/audits/raw/` の原文のファイル名に入っている数字は、フックが付ける既存の名前の形で、今回足したものではない。
- 1回目の「確かめて問題なかったこと」に挙げた数(コミット1,263、977、936、PR 167、Issue 118 と106、レビュー役249、実装役110、検証役86、試験の数)は、直しのコミットで変わっていない。[`docs/claude-usage.md`](docs/claude-usage.md) の `mm-judge` の起動12と、README の「採点役の起動が12回」も合う。
- 1回目の指摘4(dev-log の読み違えの件の出典)は、確度を低くつけ、主の記憶しだいとしていたものだ。今回の範囲の外として扱い、変わっていないことだけを見た。

関係するファイルは次のとおり。
- `~/develop/mimamori/README.md`
- `~/develop/mimamori/README.ja.md`
- `~/develop/mimamori/docs/submission.md`
- `~/develop/mimamori/docs/claude-usage.md`
- `~/develop/mimamori/video/src/numbers.ts`
- `~/develop/mimamori/scripts/usage-report.sh`
- `~/develop/mimamori/.claude/logs/usage.jsonl`
