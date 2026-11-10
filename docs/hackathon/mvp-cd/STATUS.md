# STATUS — mvp-cd（tick 3）

## 一言

スケジューラが回り、task issue は 18 件マージ済み（契約 5 件と合わせて 23/222）。worker が gate をバックグラウンドで回して結果を受け取れず止まる問題は、foreground 実行のルールで解消した。regen と research は 0 件。

## 前回のメッセージ以降

- 初回のスケジューラ（`wf_05c13c48-b92`）は、gate をバックグラウンドで回した worker が結果を受け取れずに終わり、StructuredOutput を返さない agent の例外で全体が落ちた。WORKER.md に「何もバックグラウンドで回さない」ルールを足し、agent の失敗を握る `safe()` を入れて再起動した（`wf_2e9d269f-a4c`）
- flake（`MachLoopbackTests.swift:217`）は #301 / PR #304 で直った
- S-TARGETS（#85）がマージされ、新しい module の器（21 library と executable 2 本）がそろった。依存していた issue が順に着手可能になっている
- 契約 epic のマージ後レビュー（Copilot）に対応した: #81 は #83 で解決済み、#82 は運用どおり、#83 と #305 は follow-up PR #309 で修正（`as_type` を予約、組み込み名を GPU スモークで固定、正規化コメントを冪等に）

## 進捗

| epic | マージ / 全体 |
|---|---|
| E1 契約 | 5/5 |
| E12 flake | 1/1 |
| E0 targets | 1/1 |
| E0 gallery | 2/4 |
| E2 parameter runtime | 5/21 |
| E4 health | 7/26 |
| E5 camera | 1/23 |
| E6 menu と設定 | 1/32 |
| E3 parameter UI | 0/11 |
| E7 onboarding | 0/32 |
| E8 preview | 0/22 |
| E9 authoring | 0/35 |
| E10 hygiene | 0/6 |
| E11 gaps | 0/3 |
| 合計 | 23/222 |

- 着手可能 46 件、worker は Haiku で 6 並列
- differentiator 維持 · bold 0/2 · horizon 0/9

## 直近の tick

- クローズ: #85 #86 #87 #88 #89 #90 #91 #92 #122 #124 #125 #126 #127 #128 #129 #148 #171 #301
- worker の PR は各自マージ済み。うちオーケストレーターが関わったもの: PR #303（#126、衝突を worker が解消）、#304（#301）、#309（レビュー follow-up）

## 判断キュー（暫定で走行中）

- Q1 Brief の解釈: MVP-C → MVP-D → boring tier → 暫定: そのまま
- Q2 [#73] 統合先: `hackathon/mvp-cd` → 暫定: hackathon ブランチ。`Q2 main` で切替
- Q3 Bold additions → 暫定: やらない。`bold やる` で解禁
- Q6 権限バンドル → 暫定: なしで走る。内容は `~/.config/claude/jobs/41eb249d/tmp/hk-settings.json`
- Q7 [#73] hang 系の失敗は cool-down 後も自動再試行しない → 暫定: しない。`Q7 retry` で切替

## 最近の決定

- worker は gate と CI を foreground で待つ（Bash timeout 600000、時間切れなら再実行）。subagent はバックグラウンドのコマンドの完了を受け取れないため（WORKER.md）
- 失敗は契約の修理と 1 回の再投入で扱い、worker のモデルは上げない（DECISIONS `[run]`）
- MSL の組み込み名（`uint2`、`float2x2`、`atomic_uint`、`metal`、`abs`）は予約しない。生成 struct のテキストが使わないので、フィールド名にしてもコンパイルでき、オフセットもずれない（#309）
