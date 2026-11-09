# STATUS — mvp-cd（tick 0）

## 一言

Phase 0 完了。ABI と健全性の契約を `specs/` に確定、次は issue 分解と契約 epic。

## 前回のメッセージ以降

- 暫定で確定: 統合先 `hackathon/mvp-cd`、MVP-C → MVP-D → boring tier の順、bold additions は保留
- エフェクトはホスト側で動くので、パラメータに IPC は不要と判明（スカウトの brief の前提を訂正）
- `.claude/settings.json` の権限バンドルは auto mode に止められたので未配置（Q6）

## 進捗

- boring 0/31 · differentiator 維持 · bold 0/2 · horizon 0/9

## 判断キュー（暫定で走行中）

- Q1 Brief の解釈: MVP-C → MVP-D → boring tier → 暫定: そのまま
- Q2 [#73] 統合先: `hackathon/mvp-cd` → 暫定: hackathon ブランチ。`Q2 main` で切替
- Q3 Bold additions → 暫定: やらない。`bold やる` で解禁
- Q6 権限バンドル → 暫定: なしで走る。内容は `~/.config/claude/jobs/41eb249d/tmp/hk-settings.json`
- Q7 `specs/health.md`: hang 系の失敗は cool-down 後も自動再試行しない → 暫定: しない。`Q7 retry` で切替

## 最近の決定

- ABI は manifest から `Parameters` struct を生成（`[[buffer(1)]]`、`setBytes`）
- パラメータパネルは別ウィンドウ（`.menu` スタイルの MenuBarExtra は Slider を描けない）
- 健全性の判定は `EffectCatalogUseCase` の純粋な `EffectHealthPolicy`
