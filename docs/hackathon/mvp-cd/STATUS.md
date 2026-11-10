# STATUS — mvp-cd（tick 1）

## 一言

contract epic（#75 から #79）が全部マージ済み。パラメータの ABI と pass の outcome stream が統合ブランチに入った。次は残り 10 epic の起票と worker の投入。

## 前回のメッセージ以降

- worker は jam squad ではなく、この会話の Workflow スケジューラから起動する方式に変更（DECISIONS `[run]`）。「jam で」で戻す
- 使用量上限で 3 回止まり、そのたびに途中のコミットや PR から再開した（作業の捨て直しはなし）
- #77 の worker は PR #81 を作ったところで止まったので、CI 全緑を確認して orchestrator がマージした

## 進捗

- contract 5/5（PR #80 から #84）
- boring 3/31 · differentiator 維持 · bold 0/2 · horizon 0/9
- 分解: 6 epic の契約を検証済み、残りは E4・E8 の検証、E9 の起草、新 target issue、全体の網羅チェック

## 直近の tick

- #75 merged (#80) / #77 merged (#81) / #78 merged (#82) / #76 merged (#83) / #79 merged (#84)

## 判断キュー（暫定で走行中）

- Q1 Brief の解釈: MVP-C → MVP-D → boring tier → 暫定: そのまま
- Q2 [#73] 統合先: `hackathon/mvp-cd` → 暫定: hackathon ブランチ。`Q2 main` で切替
- Q3 Bold additions → 暫定: やらない。`bold やる` で解禁
- Q6 権限バンドル → 暫定: なしで走る。内容は `~/.config/claude/jobs/41eb249d/tmp/hk-settings.json`
- Q7 [#73] hang 系の失敗は cool-down 後も自動再試行しない → 暫定: しない。`Q7 retry` で切替

## 最近の決定

- `EffectAdmission.compile` は block を持たず、`selected()` が library と block の組（`EffectSelection`）を返す（#78）
- 指紋は選択が決まる時点で刻む（#79）
- 既知の flake: `MachLoopbackTests.swift:217` が全体テストで約 2 割落ちる（パラメータ作業とは無関係、E0 の検証で判明）
