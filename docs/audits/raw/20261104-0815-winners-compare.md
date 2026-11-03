サブエージェントの報告の原文。親のセッションが確かめる前のもの。調べものの役が作業用のフォルダに書いたものを写した。ホームの道筋だけを ~ に替えた。

# 受賞作11件の公開リポジトリの読み比べ

調べた日は2026年11月4日。11件を `git clone --filter=blob:none --no-checkout` で取り、`git ls-tree` と `git show` で読んだ（取ったものは実行していない）。取った場所は `<scratchpad>/winners-repos/<repo>/`。

数えた数字の出し方は次のとおり。

- コミット数は `git rev-list --count HEAD`（既定ブランチ main）と `git rev-list --all --count`（タグと別ブランチを含む）
- Claude の共著は `git rev-list --count -i --grep='^Co-authored-by:.*claude' HEAD`（行頭一致。行頭を指定しないと「Co-Authored-By: Claude は付けない」という規則の文を数えてしまう。実際 Aria で1件ずれた）
- 日時は `git log --format=%aI` を並べ替えた最初と最後（作者のローカル時刻）
- `.claude/` の中は `git ls-tree -r --name-only HEAD` の結果

## 先に知っておくこと（読み方を変える3点）

1. Wrench Board の main は後から作り直した履歴（最初のコミットは2026年6月7日の「Initial public commit」で、4.7 の期間の外）。ただしタグ `v1.0.0-hackathon` から、期間中の履歴757コミット（2026年4月21日から4月27日）と当時のファイル一式が読める。以下、Wrench Board は main とタグの両方を書く。
2. Medkit は履歴が1コミット（2026年4月26日、まとめて入れたもの）だけ。コミットの日時から開発の進み方は読めない。
3. 4.8 Build Day の3作（Tekton、Sim Francisco、Custom Universe）に「セッションログ」があるのは、大会の参加者ガイドが提出物に求め、採点にも使うため。Tekton のリポジトリにそのガイドが入っている（[`CLAUDE_FABLE_5_BUILD_DAY_GUIDE.md`](https://github.com/tangxiya-star/Tekton/blob/HEAD/CLAUDE_FABLE_5_BUILD_DAY_GUIDE.md)）。「Deploy to a live URL and submit it with your brief, your rubric, and the session log」（16行目）、「Autonomy (15%): Judged from the session log」「Orchestration (15%): Judged from the submitted brief, rubric, and any workflow scripts」（33行目、34行目）。なお、このガイドの題は「Claude Fable 5 Build Day」で、前の調べの一覧にある「Opus 4.8 Build Day」とは呼び名が違う。同じ6月13日の大会かは、ガイドの中身だけでは確かめていない。Sim Francisco のセッションログの冒頭には「Opus 4.8」と出ている。

## 1. リポジトリごとの表

作品の略称、区分は前の役の一覧による。

### 表1 Claude の設定

| 作品（区分） | CLAUDE.md、AGENTS.md | `.claude/` の中 | MCP の設定 |
|---|---|---|---|
| CrossBeam（4.6 1位） | ルートには無い。スキルの中に `CLAUDE.md` が計7本（`crossbeam-ops` は9行、`adu-skill-development/skill/*` と `server/skills/*` は98〜103行）、`AGENTS.md` が2本（`california-adu`、98行）。自分のスキルを他の道具（AGENTS.md を読む道具）にも渡すために置いたとみえる（推測） | skills 16フォルダ（自作は `adu-city-research`、`adu-corrections-interpreter`、`cc-guide`、`crossbeam-ops`、`demo-city-review`、`demo-contractor-corrections`、`long-running-agent`、`product-demo-video`。外からのものは `document-skills`、`fal-ai`、`frontend-design`、`nano-banana`、`react-best-practices`、`shadcn`、`skill-creator`、`template-skill`）。`agents-crossbeam/.claude/skills/` にも9件（名前だけが見え、中身は `server/skills` を指すとみえる）。agents、commands、hooks、settings は無い | 無し |
| Elisa（4.6 2位） | `.claude/CLAUDE.md`（86行）、`backend/CLAUDE.md`（272行）、`backend/src/services/CLAUDE.md`（241行）、`frontend/CLAUDE.md`（88行）、`frontend/src/components/CLAUDE.md`（116行）。ディレクトリごとに分けた入れ子 | `CLAUDE.md` だけ。skills、agents、commands、hooks、settings は無い | 無し（製品の中で MCP を使う「Portal」はある） |
| TARA（4.6 Keep Thinking） | `CLAUDE.md`（70行）、`docs/CLAUDE.md`（54行） | `settings.json`（186行）だけ。hooks が入っている | 無し |
| Conductr（4.6 Special） | `CLAUDE.md`（56行）、`engine/CLAUDE.md`（92行）、`web/CLAUDE.md`（97行） | 無し | 無し |
| Medkit（4.7 1位） | `CLAUDE.md`（90行） | commands 2本（`medkit-idea-evolve`、`medkit-verify-simulation`）、skills 9本（`medkit-attending-debrief`、`medkit-guideline-curator`、`medkit-rubric-author` ほか）。agents、hooks、settings は無し | 無し（製品側は Managed Agents） |
| Wrench Board（4.7 2位） | `CLAUDE.md`。main は750行、タグ `v1.0.0-hackathon` の時点は703行 | skills 2本（`microsolder-evolve`、`microsolder-evolve-monitor`）。タグの時点でも同じ | 無し |
| Virtual Puppet Theater（4.7 Most Creative） | `CLAUDE.md`（39行） | 無し | 無し |
| ARIA（4.7 Managed Agents 賞） | main には無い。履歴の中の `de0437f` で「project-level CLAUDE.md handover」を足し、のちに main から消えている（理由は未確認） | 無し | 無し（製品の中に MCP サーバー、FastMCP、17ツール） |
| Tekton（4.8 1位） | 無し | 無し | 無し |
| Sim Francisco（4.8 2位） | 無し | 無し。`.gitignore` に `.claude` があり、README が言う `.claude/workflows/*.js` は公開されていない | 無し |
| Custom Universe（4.8 3位） | 無し | 無し | 無し |

### 表2 開発の記録

| 作品 | 記録のファイル | 日時の細かさ | 中身 |
|---|---|---|---|
| CrossBeam | [`progress.md`](https://github.com/mikeOnBreeze/cc-crossbeam/blob/HEAD/progress.md)（450行） | 時刻つきの見出し。「Tuesday, February 10 — 6:20 PM PST」のように、1日に複数回 | 作者の一人称。その時点の達成、次にやること、学び、方針の転換、バグ一覧、最後に所感 |
| Elisa | 開発記録は無い。`docs/plans/2026-02-25-*.md`、`docs/plans/2026-03-01-codebase-audit.md`、`docs/reviews/2026-03-08-code-review.md` | ファイル名に日付（日の細かさ） | 設計、計画、監査の文書。経過の記録ではない |
| TARA | `docs/TARA_*_PROMPT.md` 約20本（Claude に渡した指示文）、`docs/TARA_DAY1_TASKS.md`、`docs/TARA_MASTER_PLAN.md` | 本文に「Tuesday Feb 10」程度。ファイル名には日付なし | 指示文と計画。経過の記録は無い |
| Conductr | 無し | コミットの日時だけ | 12コミット、短い題 |
| Medkit | [`docs/evolution.md`](https://github.com/bedriyan/medkit-app/blob/HEAD/docs/evolution.md)（75行、4件） | 日（2026-04-24 が3件、2026-04-25 が1件） | 「何が変わったか、なぜ、何を置き換えるか」の型。開いた問いも書く |
| Wrench Board | main には無し。タグ `v1.0.0-hackathon` に `docs/superpowers/plans/`（24本）、`docs/superpowers/specs/`（26本）、`docs/notes/2026-04-25-vision-model-opus-vs-sonnet.md`、`docs/HACKATHON.md`。main では全部消えている | ファイル名に日付（日の細かさ） | 計画と仕様。ノートは「問い、方法、決定、再テストの条件」 |
| Virtual Puppet Theater | `docs/specs/*.md` 6本 | 無し（本文に「Draft. Pivot under construction during the final hackathon push」「Sunday evening」のような相対の言い方） | 仕様。転換の経緯が少し読める |
| ARIA | `docs/planning/ROADMAP.md`、`docs/audits/M*.md`、`docs/architecture/decisions.md`、`docs/planning/M9-polish-e2e/win-plan-48h.md` | 本文に日付。「Today: Wed Apr 22 (Day 2)」「Date: 2026-04-24 (final run 00:15 CEST)」「Written 2026-04-24 (J-2)」 | 計画、監査、決定の記録（決めたこと、比べた案、きっかけ、結果）。README は進行を GitHub の project board に案内 |
| Tekton | [`docs/session-logs/2026-06-13-164905-...txt`](https://github.com/tangxiya-star/Tekton/blob/HEAD/docs/session-logs/2026-06-13-164905-local-command-caveatcaveat-the-messages-below.txt)（4198行）、`artifacts/derivation-log.md`（85行、建築の導出の記録で開発記録ではない） | ファイル名に日時（2026-06-13 16:49）。中身は端末の生ログ | Claude Code の画面そのまま。失敗した検証の報告も残す（`verifier-report.*.failed.json`、README の記述） |
| Sim Francisco | `session-log.md`（7043行、端末の生ログ）、`NOTES.md`（106行） | 生ログに日時の行は少ない。`NOTES.md` は反復ごとで日付なし | `NOTES.md` は iter 0 から iter 4 まで、数字と「失敗、直し方、一般則」 |
| Custom Universe | [`session-log.md`](https://github.com/jss8649/image-edit-realtime-hackathon/blob/HEAD/session-log.md)（109行） | 日（「Session Log — 2026-06-13」）。各段階にコミット番号 | 作った順の要約。測った数字、詰まった所、方針の転換、レビューで見つかった不具合 |

### 表3 README、コミット、テスト

| 作品 | README の構成 | 動画の置き方 | コミット数（main / 全体）、最初と最後 | Claude 共著の割合（main） | テストと評価 |
|---|---|---|---|---|---|
| CrossBeam | 製品の紹介、「History: Claude Code hackathon, Feb 2026」、課題、3つの流れ、構成、「Skills-first design」、技術、実行方法。`progress.md` を「作り方を知りたい人へ」と案内 | README に無し（`DEMO.md` はローカルで動かす手順） | 71 / 74、2026-02-10 18:15 から 2026-10-30（期間外の追記が多い） | 57/71（80%）。Cursor の共著も14 | `agents-crossbeam/src/tests/` に段階別のスモークテスト。精度の数字は README に無い。`progress.md` に「抽出の精度95%以上」の記述 |
| Elisa | バッジ、Elisa とは、ダウンロード、開発開始、機能、「Agentic Spec-Driven Development」、構成、ドキュメント、環境変数 | 無し（GIF のみ） | 331 / 375、2026-02-10 12:57 から 2026-06-01。2026年2月が121、3月が209 | 259/331（78%） | `*.test.*` が290ファイル、CI あり。精度の数字は無し |
| TARA | 受賞表示、動画、スクリーンショット、できること、課題、「How Claude Opus 4.6 Is Used」、始め方 | 冒頭近く（14行目）にサムネイルをクリックで YouTube | 54 / 65、2026-02-11 14:57 から2026-02-24（全体では5月3日まで） | 18/54（33%） | `video/test_pipeline.py`（12項目の検証）。数字は CLAUDE.md に「12/12」。README に無し |
| Conductr | 概要、仕組み、機能、構成、AI ディレクター、使った技術、始め方、MIDI チャンネル、構成図 | 無し | 12 / 12、2026-02-11 08:53 から 2026-02-14 21:36 | 0 | C のエンジンのテスト4本（`make test`）。評価の数字は無し |
| Medkit | 概要、中身、前提、API キー、手順、実行、スクリプト、構成、「Model routing」、注意 | 無し | 1 / 1、2026-04-26 03:40 | 1/1 | `npm run verify`（データの不変条件）、`npm run test`、`backend/tests`。`rubric-smoke.ts`。数字は README に無い |
| Wrench Board | バッジ、受賞（2位）、動画、何か、なぜ作ったか、仕組み、内部、ロードマップ、始め方、ライセンス。4か国語版あり | 冒頭（27行目）に「Demo video (3 min)」のリンク | main 16 / 全体 847（タグ `v1.0.0-hackathon` が757）、期間中は2026-04-21 22:24 から 04-27 02:11。タグ内の日別は 4/21 が9、4/22 が93、4/23 が189、4/24 が210、4/25 が129、4/26 が121、4/27 が6 | main 15/16（94%）、タグ 577/757（76%） | `tests/` に262ファイル、README に「2 600+ fast tests」と「@slow accuracy-gate」。`benchmark/` に出典つきの基準データ。スキル `microsolder-evolve` は `score = 0.6 × self_MRR + 0.4 × cascade_recall` を最大化する夜間の探索 |
| Virtual Puppet Theater | 概要、使った技術、必要なもの、動かし方、ハッカソンの画像、ライセンス | 無し | 88 / 88、2026-04-22 22:41 から 2026-10-08（4月が79、5月が8、10月が1） | 86/88（98%） | `*.test.ts` が8本。評価の数字は無し |
| ARIA | バッジ、受賞、課題、機能、始め方、動かし方、構成、ドキュメントの案内、開発、Managed Agents の使い方、Behind the scenes（project board へのリンクだけ） | 無し | 377 / 377、2026-04-21 17:45 から 2026-05-18。4月23日に110、4月24日に115 | 0。Copilot の共著が53（14%） | テスト関連71ファイル、CI あり。精度の数字は無し |
| Tekton | 受賞、概要、できること、意義、今の題材、「How We Used Agents」、データと出典、パイプライン、検証、実行、技術、リポジトリ地図 | 無し（動画の代わりにデモの URL） | 74 / 80、2026-06-12 12:50 から 2026-06-23。6月12日が12、6月13日が61 | 68/74（92%）。Opus 4.8、Haiku 4.5、Fable 5 が混在 | `scripts/verify.mjs`（座標から再計測）、`done.rubric.json`（採点基準）、Playwright の画素検査。「20/20」の記述は `docs/HANDOFF_HOLLY.md` |
| Sim Francisco | 概要、短い紹介、何か、費用管理、再現手順、「The four loops」、新しい課題での再現、方法の健全さ | 無し（デモの URL） | 22 / 39、2026-06-13 13:21 から 2026-06-16。1日目に13件ほど | 0 | `cargo test`、`validate`（`rubric.yaml` で採点）、契約テスト。README に「Current weighted headline ≈ 0.84（gate 0.70）」。`NOTES.md` に iter ごとの数字（0.5336、0.6703、0.8171、0.8408、0.8490） |
| Custom Universe | 要件、Docker での実行、手動、仕組み、プロバイダ、環境変数、API、今後。Claude の記述は無し | 無し | 20 / 20、初回は2026-02-26、作業は2026-06-13 18:45（UTC）から 06-15 | 19/20（95%） | 無し。`session-log.md` に実測（約0.6秒、約1.6秒、約15秒） |

## 2. 問い1の答え

日時つきで開発の経過を書いていたのは、日の細かさ以上で、手書きまたは Claude 経由の running log があった作品が3件、生ログを置いた作品が2件、日付つきの計画や監査だけが2件。何も無かったのが4件。

### 時刻まで書いていた（1件）

CrossBeam は [`progress.md`](https://github.com/mikeOnBreeze/cc-crossbeam/blob/HEAD/progress.md) に、1日に何度も、時刻つきの見出しで書いた。

```markdown
## Wednesday, February 11 — 10:30 PM PST
**Day 2 EOD wrap-up. Big brain dump. A lot happened.**
### PDF Extraction — Lessons Learned
```

捨てた案と方針転換、詰まったこと、Claude との分担が具体的に読める。

- 詰まったこと: 「Opus 4.6 でスクリーンショットから読む精度を95%以上にしたが、26ページの束に35分かかった」
- 捨てた案と転換: 全ページを抜き出すのをやめ、修正指摘の書かれたページだけを見る `adu-targeted-page-viewer` に切り替えた（「時間の圧力が、かえって良い設計判断を促した」）
- Claude との分担: Cat Wu との質疑で見つけた内部の Guide エージェントを、`cc-guide` スキルにして自分が呼べるようにした。「Claude が作っている間の自分の考えを音声で記録した」と README が書く
- 終わりに「Built with Claude Code the entire way」と所感

README は「作り方を知りたい人はまず `progress.md`」と案内している。

### 日の細かさ、決まった型（2件）

Medkit は [`docs/evolution.md`](https://github.com/bedriyan/medkit-app/blob/HEAD/docs/evolution.md) に、型を決めて書いた。

```markdown
## YYYY-MM-DD — <one-line change>
What changed. / Why. / What it replaces. / Open questions.
```

最初の冒頭に「Kept for the "Keep Thinking" submission prize — judges want to see that the idea moved」とある。書かせるために、コマンド `/medkit-idea-evolve`（「Draft-only — waits for approval before writing」、`/loop 30m` で回す想定）を `.claude/commands/` に置いていた。捨てた案は「ゲームとして見せる案から、研修ツールとして見せる案へ」と明記してある。

Custom Universe は [`session-log.md`](https://github.com/jss8649/image-edit-realtime-hackathon/blob/HEAD/session-log.md) に、日付つきで、作った順に番号とコミット番号を付けた。

```markdown
### 1. Self-hosted realtime FLUX.2 Klein  — `960fdd0`, `6f3d25e`
- **Measured ~0.6s warm round-trip on the H100**
```

詰まったことも書く（CUDA 拡張のビルドで `cicc` が落ち、`sm_80+PTX` に変えた）。方針転換（iPhone の ARKit は取りやめ、自前の画像から3D への変換に）と、「複数エージェントによる敵対的レビューで、カメラの解放漏れが見つかり、コミット前に直した」とある。API キーは公開リポジトリなので省いたと明記。

### 端末の生ログをそのまま置いた（2件）

Tekton（4198行）と Sim Francisco（7043行）は、Claude Code の画面を丸ごと保存した。大会の採点で「自律」がセッションログから採られるため。Sim Francisco の冒頭は `/model` と `/effort`、続いて `/goal` の達成条件（`cargo test` が通る、`validate` が終了コード0、公開 URL が 200、新しい検証役と敵対的な批評役の双方が確認、など）。日付や時刻の行はほとんど無い（Tekton はファイル名に日時）。

Sim Francisco は別に `NOTES.md` を置き、「失敗、直し方、一般則」を iter 0（0.5336）から iter 4（0.8490）まで、数字つきで書いた。日付は無い。iter 4 は「敵対的な批評役が、リークの一行を見つけて直した」という記述。

### 日付つきの計画や監査だけ（2件）

ARIA は計画と監査の本文に日付を書いた（「Today: Wed Apr 22 (Day 2) ~4.5 build days remaining」、「Written 2026-04-24 (J-2 before submission)」、「Date: 2026-04-24 (final run 00:15 CEST)」）。`docs/architecture/decisions.md` は「やめた案、一度出荷してから置き換えた案」を、決定、比べた案、きっかけ、結果で書く。Q&A を Managed Agents から Messages API に戻した理由まで残る。E2E の試験報告の担当に「GitHub Copilot (autonomous)」と書いてある。

Elisa は日付つきのファイル名で計画、監査、レビューを置いた（`2026-03-01-codebase-audit.md` は3つの並列の調査を交差検証して偽陽性を除いたと書く）。経過の記録は無い。

Wrench Board の期間中（タグ `v1.0.0-hackathon`）も同じ型で、日付つきファイル名の計画24本と仕様26本があった（`docs/superpowers/plans/2026-04-22-v1-hackathon-shipping-plan.md` の冒頭に「REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development」。superpowers プラグインが出す計画の型とみえる）。main では全て消え、CLAUDE.md に「CLAUDE.md と README は更新履歴ではない。日付つきの文脈は auto-memory に置く」という編集規則がある。

### 無かった（4件）

Conductr、Virtual Puppet Theater（日付の無い仕様のみ）、TARA（指示文と計画のみ）、Wrench Board の main。Conductr は12コミットの題だけが記録。

### 問い1のまとめ

- 時刻まで書いたのは CrossBeam だけ。残りは日の細かさ
- 「捨てた案」を書いていたのは CrossBeam、Medkit、Custom Universe、ARIA（decisions.md）、Sim Francisco（NOTES.md）。「詰まったこと」は CrossBeam、Custom Universe、Sim Francisco
- Claude との分担を明示していたのは CrossBeam（自分が見て考える側、Claude が作る側）、Custom Universe（「adversarial multi-agent review」）、Sim Francisco（検証役と批評役）。Medkit は Claude に下書きさせて人が承認する型
- 書かせる仕掛けを置いたのは Medkit のコマンド1件のみ。他は人が書くか、大会の提出物の都合で生ログが残った
- 記録に残らなかった履歴は、コミットが1件に潰された Medkit、作り直された Wrench Board の main

## 3. 問い2の答え

### 数え方

「Claude の設定」を、ルートかディレクトリに置いた `CLAUDE.md`、`AGENTS.md`、`.claude/` の skills、agents、commands、hooks、settings、MCP の設定ファイルとした。入れ子の `CLAUDE.md` も1件に数える。

### 11件のうちの数

| 項目 | 件数 | 作品 |
|---|---|---|
| `CLAUDE.md` が main にある | 7 | CrossBeam（スキルの中のみ）、Elisa、TARA、Conductr、Medkit、Wrench Board、Virtual Puppet Theater |
| ルート（プロジェクト）の `CLAUDE.md` がある | 6 | 上のうち CrossBeam を除いた6件（Elisa は `.claude/CLAUDE.md`） |
| 入れ子の `CLAUDE.md`（ディレクトリごと） | 3 | Elisa（5本）、Conductr（3本）、TARA（2本） |
| `AGENTS.md` | 1 | CrossBeam（スキルの中、2本） |
| skills | 3 | CrossBeam（16フォルダ）、Medkit（9）、Wrench Board（2） |
| commands | 1 | Medkit（2本） |
| agents（サブエージェントの定義） | 0 | なし |
| hooks（Claude Code の hooks） | 1 | TARA（`.claude/settings.json`） |
| settings.json | 1 | TARA |
| MCP の設定ファイル（`.mcp.json` など） | 0 | なし |
| 何も無い（Claude の設定が1つも無い） | 3 | Tekton、Sim Francisco、Custom Universe |
| `Co-Authored-By: Claude` が付いたコミットがある | 8 | CrossBeam、Elisa、TARA、Medkit、Tekton、Custom Universe、Puppet、Wrench Board |
| 付いていない | 3 | Conductr、Sim Francisco、ARIA（ARIA は Copilot の共著が53） |

Claude 共著の割合は、main で CrossBeam 80%、Elisa 78%、TARA 33%、Tekton 92%、Custom Universe 95%、Puppet 98%、Wrench Board 94%（タグ時点 76%）。

### 共通していたもの

- 共通して多かったのは `CLAUDE.md`（7件）と、Claude の共著の記録（8件）。
- `CLAUDE.md` の中身は、構成、技術、コマンド、重要なファイルの索引が中心（Conductr、Elisa、Medkit、Wrench Board、TARA）。禁止や権限の規則が入っていたのは Puppet（「Never deploy unless explicitly requested」）、Wrench Board（「Never `git push` without explicit authorization」、「幻覚の部品番号を出さない」）、Medkit（下の抜き出し）、Elisa（構造を変えたら同じコミットでドキュメントも直す表）。
- 長さは39行から750行まで幅がある。入れ子で分けた Elisa（5本で約800行）と、1本に集めた Wrench Board（750行）は対照的。
- 「進め方の規則」で似ていたもの: コミットの型（Wrench Board、Puppet が conventional commits）、デプロイやプッシュを自動でやらない（Puppet、Wrench Board、TARA の hooks が `git push` を止める）、確かめてから終わる（Wrench Board の「make test を流してから完了と言う」、TARA の Stop フックの自己点検）。

### 上位ほど多かったもの

- skills を置いた3件（CrossBeam、Medkit、Wrench Board）は、4.6 と 4.7 の1位と2位の4件のうち3件。同じ4件のもう1件、Elisa は入れ子の `CLAUDE.md` を持つ。つまり4.6 と 4.7 の1位と2位の4件は、全て skills か入れ子の `CLAUDE.md` のどちらかを持ち、特別賞の4件（TARA、Conductr、Puppet、ARIA）は skills を持たなかった。
- 4.8 Build Day の上位3件は、Claude の設定が1つも無い。代わりに、大会の求めに合わせた簡潔な指示書、採点基準、セッションログを持つ。Tekton の `done.rubric.json`（採点基準の4項目に重みづけし、「自律」「統率」の項目も入れる）、Sim Francisco の `BRIEF.md`（262行、冒頭で「Autonomy + Orchestration の採点に合わせて」と書く）と `rubric.yaml`（さらに都市違いの4本）。この2件は、参加者ガイドの「ブリーフ、採点基準、セッションログ」に直接合わせた作りで、対して Custom Universe は session-log のみ。
- 4.7 の1位 Medkit は `CLAUDE.md` に、他の作品に無い「やらないこと」を書いていた。

  ```markdown
  - Don't create specialist sub-agents (`triage-expert`, `pharmacology-expert`, …). Use skills in `.claude/skills/` and let Claude compose them.
  - Don't write long rigid bullet lists of rules here — Opus 4.7 follows them literally and over-triggers. Encode hard rules as hooks or lint instead.
  ```

  出典: [`CLAUDE.md`](https://github.com/bedriyan/medkit-app/blob/HEAD/CLAUDE.md)。ただし、その Medkit も hooks は置いていない。

### どれにも無かったもの

- サブエージェント定義（`.claude/agents/`）
- MCP の設定ファイル
- 公開された `.claude/workflows`（Sim Francisco は README が言うが、`.gitignore` で隠れている）
- Claude Code の hooks（TARA の1件のみ）
- 精度や評価の数字を README に載せた作品が Sim Francisco の1件のみ（Wrench Board は「2 600+ fast tests」「@slow accuracy-gate」、Tekton は README に数字なし）
- README に動画のリンクを置いた作品は TARA（冒頭近くのサムネイル）と Wrench Board（冒頭の1行）の2件だけ。他は提出フォーム側で出すためとみえる（推測）

### README で Claude の使い方に節を割いていた作品

- TARA の「How Claude Opus 4.6 Is Used」（最後に「Built with Claude Code ... multi-agent development with hooks」と一行）
- Tekton の「How We Used Agents」（簡潔な指示書と採点基準、決定的な検証、失敗した報告の保存、並列の調査役と順番の実装役と敵対的な検証役）
- Sim Francisco の「The four loops」（`/goal`、検証役と批評役、動的ワークフロー、継続的なフィードバック）
- Wrench Board（Knowledge Factory、夜間探索ループ）
- Medkit のモデルの使い分けの表
- CrossBeam の「Skills-first design」と `progress.md` への案内

節が無いのは Conductr、Elisa（製品の紹介が主）、Puppet、ARIA（project board へのリンクのみ）、Custom Universe。

## 4. 前の調べとの突き合わせ

前の調べ: 「公開リポジトリを確認できた受賞作8件のうち、サブエージェントの定義を置いていたのは0件、フックは1件」。

今回の11件を数え直した。

| 項目 | 今回の数 | 数えたコマンド |
|---|---|---|
| サブエージェントの定義 | 0件 | `git ls-tree -r --name-only HEAD \| grep -E '\.claude/agents'` が全11件で0 |
| フック（Claude Code の hooks） | 1件（TARA） | `.claude/settings.json` の `hooks` キー。SessionStart、PermissionRequest 32件（npm や git の安全な操作を自動で許可）、PreToolUse（`rm -rf`、`git push`、`git checkout`、`git merge`、`git reset --hard` を止める）、Stop、SubagentStop（どちらも自己点検の prompt フック）、PreCompact（会話の控えを保存） |

結果は合う。ただし次の注意がある。

- 前回の8件がどれかは前の調べのファイルを読んでおらず、合う理由の根拠は示せない。差の3件（Custom Universe、Sim Francisco、Tekton のどれか）は今回新しく読んだ。3件とも agents も hooks も無い。
- Sim Francisco には `.githooks/pre-push`（Git のフック、`cargo test` と `validate --smoke` を流す）があるが、Claude Code の hooks ではないので1件に数えていない。数え方によっては「フック2件」となる。
- サブエージェントの定義ファイルは無くても、実行時に使った作品はある。Sim Francisco（検証役と批評役、`/goal` の指示に書く）、Tekton（視覚の検証役、並列の調査役）。CrossBeam は Claude Agent SDK の製品（`agents-crossbeam/`）の中で実行時のサブエージェントを使うが、Claude Code の定義ファイルとは別。

## 確かめられなかったこと、数え方の限界

- Wrench Board の main が作り直された理由は、記録が見つからず未確認。タグ `v1.0.0-hackathon` を取る以外の確かめ方はない（作者に聞く）。
- ARIA の `CLAUDE.md` が main から消えた理由は未確認。消えた時のコミットを見ていない（`git log --diff-filter=D -- CLAUDE.md` で確かめられる）。
- Elisa、CrossBeam、TARA、Tekton、Sim Francisco には main に入っていない別ブランチがある（全体の数との差）。そこにだけ置かれたファイルは読んでいない。
- Tekton は6月12日付の12コミットが大会の前日。大会の規則との関係は判断していない（日付は `git log --format=%aI` のとおり）。
- PostVisit.ai、Maieutic、MaestrIA の3件は公開リポジトリが無く、対象外。
- 4.6 の受賞発表は5件分しか載っておらず、欠けた1件は確かめられない（前の調べのとおり）。
- デモ動画は見ていない。動画の中で Claude をどう見せたかの文は、README に Tekton の「How We Used Agents」など節として見つかったもの以外は拾えていない。
