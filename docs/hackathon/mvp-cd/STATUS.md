# STATUS — mvp-cd（tick 2）

## 一言

残り 11 epic を 217 issue（#85 から #301）に分解して起票し、スケジューラを起動した。worker は Haiku で 6 並列、依存が片付いた issue から順に着手する。

## 前回のメッセージ以降

- 分解は epic ごとに起草、検証、全体の critic の 3 段で行った。critic が穴を 3 件見つけて追加した（E11: 無効な effect を cycle で飛ばす、設定リセットでカメラのメニューを再起動、無効な effect のメニュー画面）
- 新しい module は S-TARGETS（#85）1 件だけが `Package.swift` と lint の許可表に入れる（21 library と executable 2 本）
- 失敗した issue は、判断役の agent が契約（issue 本文）を直してから Haiku に 1 回だけ再投入する。2 回目も駄目なら保留にして、ここに書く
- gate の既知の flake（`MachLoopbackTests.swift:217`）は #301 が最優先で直す。直るまでは、その 1 件だけで赤なら worker が gate をもう 1 回だけ回す

## 進捗

- contract 5/5（PR #80 から #84）
- 起票 217 件、着手可能 42 件、マージ 0 件
- boring 3/31 · differentiator 維持 · bold 0/2 · horizon 0/9

## 直近の tick

- 起票: #85 から #300（216 件）、#301（flake）
- スケジューラ起動（Workflow `wf_05c13c48-b92`、並列 6）

## 判断キュー（暫定で走行中）

- Q1 Brief の解釈: MVP-C → MVP-D → boring tier → 暫定: そのまま
- Q2 [#73] 統合先: `hackathon/mvp-cd` → 暫定: hackathon ブランチ。`Q2 main` で切替
- Q3 Bold additions → 暫定: やらない。`bold やる` で解禁
- Q6 権限バンドル → 暫定: なしで走る。内容は `~/.config/claude/jobs/41eb249d/tmp/hk-settings.json`
- Q7 [#73] hang 系の失敗は cool-down 後も自動再試行しない → 暫定: しない。`Q7 retry` で切替

## 最近の決定

- 失敗は契約の修理と 1 回の再投入で扱い、worker のモデルは上げない（DECISIONS `[run]`）
- flake は増幅で直す: register を 64 回失敗させて、新しい receive right が 32 未満（#301）
- `EffectAdmission.compile` は block を持たず、`selected()` が library と block の組（`EffectSelection`）を返す（#78）
