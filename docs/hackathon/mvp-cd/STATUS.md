# STATUS — mvp-cd（tick 7）

## 一言

マージは 139/223 で、tick 5 から 40 件進んだ（計画外の flake 修正 #373 を足すと 140 件）。09:17 ごろに 2 本の run が両方止まったので、15:00 に再開した。再開直後の run 3 は負荷で全滅したが、gate の待ち方を直した run 4 は 13 件を失敗なしでマージした。regen は 0 件、research は 0 件。撮影を持ち越している UI task（`hk:shot-pending`）も 0 件。

## 前回のメッセージ以降

- run 3（8 並列、gate slot 5）は最初の 9 回の試行（8 件と、その 1 件の再投入）がすべて timeout で終わった。load average が 100 を超え、gate が Bash 1 回の上限 600 秒に収まらなかった。時間切れの gate は harness が background で走らせ続けるので、「もう一度走らせる」決まりが gate を積み重ねていた。gate は切り離して起動し、待つ側は 1 回 9 分以内で緑・赤・死亡・継続中を答える形に変えた。worker は最大 5 並列、gate slot は 3（WORKER.md、PRODUCT.md、DECISIONS、8bc3b5c）
- run 4（`wf_7f8b9b59-b72`）はこの形で走っており、load は 2〜26 に収まっている。run 3 で切れた 8 件（#140、#166、#199、#239、#251、#273、#280、#290）は、run 4 でどれもマージした
- PR #432 は `codecov/patch` が upload 後 30 分返事をせず、worker が待ち続けた。test job を再実行して返事を引き出し、マージした。どの check も required ではないので、codecov だけが保留なら進んでよいと WORKER.md step 6 に足した（63e94c6）
- ディスクの空きが 43 GiB まで減っていた。終わった worker の `.build`（1 個 1.2 GiB 前後）を消して 169 GiB に戻した。monitor を張り直すたびに続けて消す
- 重複していた #325 と #320 を閉じ、#428 をマージした（#99）

## 進捗

| epic | マージ / 全体 |
|---|---|
| E1 契約 | 5/5 |
| E12 flake | 1/1 |
| E0 targets | 1/1 |
| E0 gallery | 4/4 |
| E6 menu と設定 | 28/32 |
| E7 onboarding | 22/32 |
| E5 camera | 19/24 |
| E4 health | 14/26 |
| E2 parameter runtime | 12/21 |
| E8 preview | 9/22 |
| E9 authoring | 16/35 |
| E3 parameter UI | 7/11 |
| E10 hygiene | 1/6 |
| E11 gaps | 0/3 |
| 合計 | 139/223 |

- worker は Haiku で 5 並列。スケジューラは `wf_7f8b9b59-b72`。残りは 84 件で、着手中は #123、#220、#240、#264、#274
- differentiator 維持 · bold 0/2 · horizon 0/9

## 直近の tick

- クローズ（tick 5 以降）: #97–#100、#104、#113–#117、#133–#135、#140、#164–#166、#195、#197–#199、#222、#223、#225、#239、#250、#251、#260、#261、#265、#266、#269–#273、#280、#290
- 起票: なし

## 判断キュー（暫定で走行中）

- Q1 Brief の解釈: MVP-C → MVP-D → boring tier → 暫定: そのまま
- Q2 [#73] 統合先: `hackathon/mvp-cd` → 暫定: hackathon ブランチ。`Q2 main` で切替
- Q3 Bold additions → 暫定: やらない。`bold やる` で解禁
- Q6 権限バンドル → 暫定: なしで走る。内容は `~/.config/claude/jobs/41eb249d/tmp/hk-settings.json`
- Q7 [#73] hang 系の失敗は cool-down 後も自動再試行しない → 暫定: しない。`Q7 retry` で切替
- Q8 画面ロック中の UI 撮影（#97 で発覚、02:50）→ 暫定: ゲートが green ならコードを先にマージし、撮影は `hk:shot-pending` で持ち越す。ロック解除後にオーケストレーターがまとめて撮って読む。`Q8 hold` で UI issue を朝まで止める

## 最近の決定

- worker の gate は切り離して起動し、制限時間のある呼び出しで待つ。worker は 5 並列、gate slot は 3（run 3 の全滅から）
- `codecov/patch` だけが保留のときはマージに進む。codecov の失敗は赤のまま（#432）
- CI の負荷だけで制限を超えるテストは、長い制限を持つ別の suite に移す。ハング監視の suite は 1 分のまま（#373）
- 選んだカメラ format は、device のロックを `startRunning` から `stop()` まで保持して保つ。preset の経路ではロックを取らない（#357）
- ロック中の UI task は撮影を持ち越してマージする（Q8）
- 失敗は契約の修理と 1 回の再投入で扱い、worker のモデルは上げない（DECISIONS `[run]`）
