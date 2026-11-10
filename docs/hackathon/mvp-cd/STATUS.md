# STATUS — mvp-cd（tick 4）

## 一言

マージは 69/223 で、tick 3 から 46 件進んだ。regen は 0 件。research は 2 件出て、どちらも回答済み（#97 は画面ロック、#153 は macOS のカメラ format）。CI に新しい flake が 1 件出ている（`HostAbsenceIntegrationTests` の 60 秒制限）。worker が失敗したジョブだけを再実行してしのいでいる。

## 前回のメッセージ以降

- #97（ギャラリーの撮影）: 窓が撮れなかった原因は画面ロック（02:50 の時点で `CGSSessionScreenIsLocked = Yes`）。ロック中の UI task は、ゲートが green ならコードを先にマージし、撮影は `hk:shot-pending` で持ち越す。ロックが解けたらまとめて撮って読む（Q8、b098f4f）
- #153（カメラ format）: macOS には `.inputPriority` がない。選んだ format を保つため、device のロックを稼働中ずっと保持する follow-up として #357 を起票した（DECISIONS、27b07c3）
- #213: CI 待ちで時間切れになったが、修理役が「作り直さず PR を仕上げる」手順を契約に足して再投入し、マージされた
- 新しい flake: `HostAbsenceIntegrationTests.swift:321`（`leaseBalancePropertyCoverage`）が、CI の負荷で 60 秒の制限を超える（#154、#186、#214 で発生）。50 個の seed を 1 つのテストで直列に回している。計測中で、#301 と同じく最優先の task にする

## 進捗

| epic | マージ / 全体 |
|---|---|
| E1 契約 | 5/5 |
| E12 flake | 1/1 |
| E0 targets | 1/1 |
| E0 gallery | 3/4 |
| E6 menu と設定 | 18/32 |
| E7 onboarding | 12/32 |
| E4 health | 10/26 |
| E2 parameter runtime | 8/21 |
| E5 camera | 8/24 |
| E8 preview | 2/22 |
| E9 authoring | 1/35 |
| E3 parameter UI | 0/11 |
| E10 hygiene | 0/6 |
| E11 gaps | 0/3 |
| 合計 | 69/223 |

- worker は Haiku で 6 並列。スケジューラは `wf_2e9d269f-a4c`
- differentiator 維持 · bold 0/2 · horizon 0/9

## 直近の tick

- クローズ（tick 3 以降）: #93–#96、#130–#132、#149–#154、#156、#172–#187、#190、#203–#214、#235、#236、#257
- 起票: #357（カメラ format のロック保持）

## 判断キュー（暫定で走行中）

- Q1 Brief の解釈: MVP-C → MVP-D → boring tier → 暫定: そのまま
- Q2 [#73] 統合先: `hackathon/mvp-cd` → 暫定: hackathon ブランチ。`Q2 main` で切替
- Q3 Bold additions → 暫定: やらない。`bold やる` で解禁
- Q6 権限バンドル → 暫定: なしで走る。内容は `~/.config/claude/jobs/41eb249d/tmp/hk-settings.json`
- Q7 [#73] hang 系の失敗は cool-down 後も自動再試行しない → 暫定: しない。`Q7 retry` で切替
- Q8 画面ロック中の UI 撮影（#97 で発覚、02:50）→ 暫定: ゲートが green ならコードを先にマージし、撮影は `hk:shot-pending` で持ち越す。ロック解除後にオーケストレーターがまとめて撮って読む。`Q8 hold` で UI issue を朝まで止める

## 最近の決定

- 選んだカメラ format は、device のロックを `startRunning` から `stop()` まで保持して保つ。preset の経路ではロックを取らない（#357）
- ロック中の UI task は撮影を持ち越してマージする（Q8）
- worker は gate と CI を foreground で待つ（WORKER.md）
- 失敗は契約の修理と 1 回の再投入で扱い、worker のモデルは上げない（DECISIONS `[run]`）
