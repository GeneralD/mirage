# STATUS — mvp-cd（tick 9）

## 一言

マージは 206/223 で、tick 8 から 34 件進んだ（計画外の flake 修正 #373 を足すと 207 件）。run 4 はここまで 80 件をマージし、失敗も保留も 0 件。regen は 0 件、research は 0 件。画面ロック中に撮れなかった UI task が 5 件あり、撮影を持ち越している（`hk:shot-pending`）。

## 前回のメッセージ以降

- tick 8 から 3 時間、介入なしで進んだ。同梱エフェクト 3 本（Vignette、Pixelate、Duotone）、はじめてのエフェクトのチュートリアル、PR テンプレートと issue フォーム、タグごとのリリースノートが入った。E2 parameter runtime と E3 parameter UI は全件マージした
- 撮影を持ち越した UI task: #121、#144、#169、#202、#254。コードはゲートが緑でマージ済み。ロックが解けたらオーケストレーターがまとめて撮って読む（Q8）
- 置き換えた PR を worker が自分で閉じる流れが回っている（#493 → #495、#492 → #498）
- 新しく出た PR に、View の `body` を評価するテストはない。tick 8 で、契約の食い違いから PR #467 の CI が 30 分止まった件を直した（WORKER.md 手順 3、DECISIONS）。前に入った分は follow-up #478 で消す

## 進捗

| epic | マージ / 全体 |
|---|---|
| E1 契約 | 5/5 |
| E12 flake | 1/1 |
| E0 targets | 1/1 |
| E0 gallery | 4/4 |
| E2 parameter runtime | 21/21 |
| E3 parameter UI | 11/11 |
| E4 health | 25/26 |
| E5 camera | 22/24 |
| E6 menu と設定 | 30/32 |
| E7 onboarding | 30/32 |
| E8 preview | 20/22 |
| E9 authoring | 32/35 |
| E10 hygiene | 4/6 |
| E11 gaps | 0/3 |
| 合計 | 206/223 |

- worker は Haiku で 5 並列。スケジューラは `wf_7f8b9b59-b72`。残りは 17 件で、着手中は #147、#170、#196、#201、#232
- 残り: #147、#170、#196、#201、#232、#234、#255、#256、#284、#291、#292、#296–#300、#357
- differentiator 維持 · bold 0/2 · horizon 0/9

## 直近の tick

- クローズ（tick 8 以降）: #102、#103、#108–#110、#120、#121、#138、#139、#143–#146、#169、#202、#230、#231、#233、#242、#243、#249、#253、#254、#263、#278、#279、#281–#283、#288、#289、#293–#295
- 起票: なし

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
