# STATUS — mvp-cd（tick 5）

## 一言

マージは 99/223 で、tick 4 から 30 件進んだ（計画外の flake 修正 #373 を足すと 100 件）。regen は 1 件（#193）で、修理役が契約を直して再投入し、マージされた。research は 0 件。CI の starvation flake は #377 で直した。撮影を持ち越している UI task（`hk:shot-pending`）は 0 件。

## 前回のメッセージ以降

- flake: `leaseBalancePropertyCoverage` は CI の負荷だけで 60 秒の制限を超えていた。3 分の制限を持つ別の suite に移した（#373、PR #377）。1 分の制限はハングを見張るためのものなので、元の suite に残した（DECISIONS、52a3dfe）
- #193（harness の menu を、フレームを捨てる sink の下で作る）: 契約の Scope に `scripts/check-dev-substitutions.sh` が入っておらず、worker は lint に掛かる手前で止まった。修理役が lint の変更を Scope に足し、Rule 2 も menu まで確かめるよう強めて再投入し、マージされた
- 修理と再投入の仕組みは、ここまで #213 と #193 の 2 件を通した。worker のモデルは上げていない

## 進捗

| epic | マージ / 全体 |
|---|---|
| E1 契約 | 5/5 |
| E12 flake | 1/1 |
| E0 targets | 1/1 |
| E0 gallery | 3/4 |
| E6 menu と設定 | 24/32 |
| E7 onboarding | 19/32 |
| E5 camera | 16/24 |
| E4 health | 10/26 |
| E2 parameter runtime | 8/21 |
| E8 preview | 6/22 |
| E9 authoring | 4/35 |
| E3 parameter UI | 2/11 |
| E10 hygiene | 0/6 |
| E11 gaps | 0/3 |
| 合計 | 99/223 |

- worker は Haiku で 6 並列。スケジューラは `wf_2e9d269f-a4c`。残りは 122 件
- differentiator 維持 · bold 0/2 · horizon 0/9

## 直近の tick

- クローズ（tick 4 以降）: #111、#112、#155、#157–#163、#188、#189、#191–#194、#215–#219、#221、#224、#237、#238、#244、#246、#258、#259、#262、#267、#268、#373
- 起票: #373（CI starvation の flake）

## 判断キュー（暫定で走行中）

- Q1 Brief の解釈: MVP-C → MVP-D → boring tier → 暫定: そのまま
- Q2 [#73] 統合先: `hackathon/mvp-cd` → 暫定: hackathon ブランチ。`Q2 main` で切替
- Q3 Bold additions → 暫定: やらない。`bold やる` で解禁
- Q6 権限バンドル → 暫定: なしで走る。内容は `~/.config/claude/jobs/41eb249d/tmp/hk-settings.json`
- Q7 [#73] hang 系の失敗は cool-down 後も自動再試行しない → 暫定: しない。`Q7 retry` で切替
- Q8 画面ロック中の UI 撮影（#97 で発覚、02:50）→ 暫定: ゲートが green ならコードを先にマージし、撮影は `hk:shot-pending` で持ち越す。ロック解除後にオーケストレーターがまとめて撮って読む。`Q8 hold` で UI issue を朝まで止める

## 最近の決定

- CI の負荷だけで制限を超えるテストは、長い制限を持つ別の suite に移す。ハング監視の suite は 1 分のまま（#373）
- 選んだカメラ format は、device のロックを `startRunning` から `stop()` まで保持して保つ。preset の経路ではロックを取らない（#357）
- ロック中の UI task は撮影を持ち越してマージする（Q8）
- 失敗は契約の修理と 1 回の再投入で扱い、worker のモデルは上げない（DECISIONS `[run]`）
