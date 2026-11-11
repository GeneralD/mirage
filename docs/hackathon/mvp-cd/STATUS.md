# STATUS — mvp-cd（tick 8）

## 一言

マージは 172/223 で、tick 7 から 33 件進んだ（計画外の flake 修正 #373 を足すと 173 件）。run 4 はここまで 46 件をマージし、失敗も保留も 0 件。CI の `test` が 30 分止まった件は、契約の食い違いが原因だった。直してからは止まっていない。regen は 0 件、research は 0 件、撮影の持ち越し（`hk:shot-pending`）も 0 件。

## 前回のメッセージ以降

- #228 の PR #467 で、CI の `test` ジョブがテスト開始 2 秒後から無出力になり、30 分後に取り消された。原因は、Done に残っていた定型の「Interface の各項目に単体テスト」が、本文の「単体テストは付かない」と食い違っていたこと。worker は Done に従い、View の `body` を評価するテストを書いた。同じ食い違いのある 5 件（#168、#170、#228、#232、#357）の本文を直し、WORKER.md の手順 3 に「テストを付けない契約が優先」「View の body を評価するテストは書かない」と足した（2641185、DECISIONS 4e87a00）
- 走っていた worker が書いた View テストは、PR ブランチから消した（PR #473、#474）。どちらも `test` が緑になってマージされ、原因はこのテストだったと確かめた
- #200 の PR #476 も既存のテストファイルに `body` の評価を 4 か所足したが、CI は緑だったので止めずに通した。`Tests/` に残る body の評価は follow-up #478 でまとめて消す
- 置き換えた PR は worker が自分で閉じるようになった（#467 は worker が閉じた。WORKER.md 手順 7）
- ディスクの空きは 166 GiB で落ち着いている。monitor を張り直すたびに、終わった worker の `.build` を消している

## 進捗

| epic | マージ / 全体 |
|---|---|
| E1 契約 | 5/5 |
| E12 flake | 1/1 |
| E0 targets | 1/1 |
| E0 gallery | 4/4 |
| E6 menu と設定 | 29/32 |
| E7 onboarding | 27/32 |
| E5 camera | 21/24 |
| E4 health | 19/26 |
| E2 parameter runtime | 16/21 |
| E8 preview | 15/22 |
| E9 authoring | 24/35 |
| E3 parameter UI | 9/11 |
| E10 hygiene | 1/6 |
| E11 gaps | 0/3 |
| 合計 | 172/223 |

- worker は Haiku で 5 並列。スケジューラは `wf_7f8b9b59-b72`。残りは 51 件で、着手中は #102、#230、#253、#278、#288
- differentiator 維持 · bold 0/2 · horizon 0/9

## 直近の tick

- クローズ（tick 7 以降）: #101、#105–#107、#118、#119、#123、#136、#137、#141、#142、#167、#168、#200、#220、#226–#229、#240、#241、#245、#247、#248、#252、#264、#274–#277、#285–#287
- 起票: #478（follow-up: View の body を評価するテストを消す）

## 判断キュー（暫定で走行中）

- Q1 Brief の解釈: MVP-C → MVP-D → boring tier → 暫定: そのまま
- Q2 [#73] 統合先: `hackathon/mvp-cd` → 暫定: hackathon ブランチ。`Q2 main` で切替
- Q3 Bold additions → 暫定: やらない。`bold やる` で解禁
- Q6 権限バンドル → 暫定: なしで走る。内容は `~/.config/claude/jobs/41eb249d/tmp/hk-settings.json`
- Q7 [#73] hang 系の失敗は cool-down 後も自動再試行しない → 暫定: しない。`Q7 retry` で切替
- Q8 画面ロック中の UI 撮影（#97 で発覚、02:50）→ 暫定: ゲートが green ならコードを先にマージし、撮影は `hk:shot-pending` で持ち越す。ロック解除後にオーケストレーターがまとめて撮って読む。`Q8 hold` で UI issue を朝まで止める

## 最近の決定

- テストを付けない契約では、定型の「Interface の各項目に単体テスト」を Done に残さない。View の `body` を評価するテストは書かない（#228）
- 置き換えた PR は、`-r1` の PR を開いた worker が閉じる（#442）
- worker の gate は切り離して起動し、制限時間のある呼び出しで待つ。worker は 5 並列、gate slot は 3（run 3 の全滅から）
- `codecov/patch` だけが保留のときはマージに進む。codecov の失敗は赤のまま（#432）
- CI の負荷だけで制限を超えるテストは、長い制限を持つ別の suite に移す。ハング監視の suite は 1 分のまま（#373）
- 失敗は契約の修理と 1 回の再投入で扱い、worker のモデルは上げない（DECISIONS `[run]`）
