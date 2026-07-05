# claude-harness-universal — 通用工作框架

## 本文件目的

本文件是整套 harness 的入口:說明這套框架解決什麼問題、各檔案的角色,以及最重要的「載入順序」——在什麼場景、按什麼順序把哪些文件交給執行模型。

## 如何使用本文件

1. 第一次接觸本套件:讀完「這套 harness 是什麼」與「目錄結構」,再看「快速開始」選擇你的場景。
2. 日常使用:直接查「載入順序」與「任務原型判定」兩節,決定本次要載入哪些檔案。
3. context 吃緊時:依「context 預算有限時的裁剪順序」裁剪。
4. 要新增或修改任何文件:先讀文末「維護原則」,共用詞彙不可漂移。

## 這套 harness 是什麼

這是一套「通用工作框架」:把高階模型面對陌生任務時的**規劃流程、判斷框架、品質標準與已知失手模式**,外化成一組協議文件與模板。執行模型(如 Opus)接到任何任務時,不靠即興發揮,而是:照 `PLANNING.md` 八階段推進、照 `DECISION_PROTOCOL.md` 裁決與升級、照 `GENERAL_RUBRIC.md` 自評把關、對照 `ANTIPATTERNS.md` 避開已知的坑、以 `exemplars/` 的黃金示範為行為樣板。品質由協議保證,而非由模型天分保證。

解決的問題:較弱的執行模型最常敗在**過早動手、範圍蔓延、幻覺 API/數據、只走快樂路徑、掩飾不確定性、破壞既有介面、過度工程**——這些都不是能力問題,而是流程與紀律問題,因此可以用協議修復。

## 目錄結構

```text
claude-harness-universal/
├── README.md                  # 本文件:總覽、載入順序、快速開始
├── PLANNING.md                # U1 通用規劃協議:八階段流程+提問框架+規劃輸出模板(最重要)
├── GENERAL_RUBRIC.md          # U2 跨領域品質 Rubric:R1-R8 八維度、自評指令、Grader Prompt
├── ANTIPATTERNS.md            # U3 反模式庫:六原型共 68 條「情況X→絕不做Y→改做Z→因為W」
├── DECISION_PROTOCOL.md       # U5 決策與升級協議:取捨優先序、風險分級、停問觸發、不確定性規範
├── exemplars/                 # U4 黃金示範庫(本包靈魂)
│   ├── README.md              #   few-shot 用法與六組題目一覽
│   └── {原型}/                #   software-implementation / system-design / research-analysis
│       ├── EXEMPLAR.md        #   / technical-writing / debugging / data-analysis 各一組:
│       └── CRITIQUE.md        #   思考外顯的完整示範+同題劣質解逐點批改
├── bootstrap/                 # U6 專案啟動套件
│   ├── CLAUDE.md.template     #   新專案 CLAUDE.md 母版(固定工作流+{{專案變數}})
│   ├── BOOTSTRAP_PROMPT.md    #   給執行模型的一段式啟動指令(規劃→生成文件→確認後才實作)
│   └── templates/
│       ├── SPEC_TEMPLATE.md       # 規格模板(目標/非目標/FR/NFR/驗收)
│       ├── TASKS_TEMPLATE.md      # WBS 模板(依賴/規模/風險級/驗收條件/狀態)
│       ├── ADR_TEMPLATE.md        # 架構決策紀錄模板+ADR 觸發清單
│       ├── CHECKLIST_TEMPLATE.md  # 交付前檢查清單(規劃/反模式/Rubric 自評/收尾)
│       └── verify.sh              # 驗證腳本骨架(lint/test/build/custom,可直接執行)
└── evals/                     # U7 校準題組
    ├── README.md              #   施測方式、判卷、低分回補迴路、18 題一覽
    └── {原型}.md              #   每原型 3 題(基礎/應用/陷阱),含標準答案與評分說明
```

## 載入順序(核心)

### A. 任何任務(基礎三件套,依序載入)

1. `PLANNING.md` — 決定「怎麼開始、什麼時候可以動手」。
2. `DECISION_PROTOCOL.md` — 決定「怎麼選、什麼時候停下來問」。
3. `GENERAL_RUBRIC.md` — 決定「怎樣才算可以交付」。

### B. 判定任務原型後追加

4. `ANTIPATTERNS.md` 對應原型的一節(不必整份;開頭的嚴重度定義+該原型節+快速自查)。
5. `exemplars/{原型}/EXEMPLAR.md` 作為 few-shot(貼在任務描述之前);context 允許再加 `CRITIQUE.md`。

### C. 新專案啟動

`bootstrap/BOOTSTRAP_PROMPT.md` 的啟動指令 + `bootstrap/` 模板組(搭配 A 的三件套)。流程:執行模型走完規劃階段 → 用模板生成 SPEC/tasks/ADR/CHECKLIST/verify.sh/CLAUDE.md → 使用者確認後才實作。

### D. 定期校準

`evals/` 依其 README 施測:乾淨對話測基線 → 加載 harness 測增益 → Grader Prompt 判卷 → 低分維度回補示範與規則。

### context 預算有限時的裁剪順序

各文件規模(約):PLANNING 480 行、DECISION_PROTOCOL 300 行、GENERAL_RUBRIC 300 行、ANTIPATTERNS 全文 600 行(單一原型節約 100 行)、EXEMPLAR 360-540 行、CRITIQUE 140-260 行。

由後往前砍(砍到放得下為止):

1. 先砍 `CRITIQUE.md`(保留 EXEMPLAR)。
2. 再裁 `EXEMPLAR.md`:保留【澄清】~【驗收定義】,截短【執行】(詳見 exemplars/README.md)。
3. `ANTIPATTERNS.md` 只留該原型節的「快速自查」清單。
4. `GENERAL_RUBRIC.md` 只留〈交付前自評指令〉一節(自評表自帶八維度名稱)。
5. `DECISION_PROTOCOL.md` 只留第 2 節(風險分級)與第 3 節(停問觸發條件)。
6. `PLANNING.md` 是底線:再擠也至少保留「八階段總覽」表+「規劃輸出模板」——模板填寫本身會強迫走完各階段。

## 任務原型判定

在 PLANNING.md 階段 2「問題重述」時判定,依此決定載入 B 組的哪些檔案:

| slug | 中文 | 前綴 | 典型任務樣貌 |
|---|---|---|---|
| software-implementation | 軟體實作 | SW | 寫新功能、新模組、腳本、測試;交付物是程式碼 |
| system-design | 系統設計 | SD | 出架構/設計文件、元件與資料模型、技術選型;交付物是設計 |
| research-analysis | 研究分析 | RA | 回答開放問題、比較方案、提建議;交付物是分析報告 |
| technical-writing | 技術寫作 | TW | README、指南、Runbook、API 文件;交付物是給人讀的文件 |
| debugging | 除錯排錯 | DB | 從症狀找根因並修復;交付物是診斷+修法+防護 |
| data-analysis | 資料分析 | DA | 從數據得出結論或決策建議;交付物是判讀與建議 |

**混合型任務**:以「主要交付物」判定主原型(例如「查明 bug 並寫事後報告」→ 主原型 DB,報告部分參照 TW);載入主原型的示範,context 允許時加貼次原型的【澄清】~【驗收定義】段。

## U1-U7 對照表

| 交付項 | 內容 | 檔案 |
|---|---|---|
| U1 | 通用規劃協議 | `PLANNING.md` |
| U2 | 通用品質 Rubric | `GENERAL_RUBRIC.md` |
| U3 | 通用反模式庫 | `ANTIPATTERNS.md` |
| U4 | 任務原型黃金示範庫 | `exemplars/`(六組 EXEMPLAR+CRITIQUE 與 README) |
| U5 | 決策與升級協議 | `DECISION_PROTOCOL.md` |
| U6 | 專案啟動套件 | `bootstrap/`(CLAUDE.md 母版、五個模板、啟動指令) |
| U7 | 通用校準題組 | `evals/`(六原型×3 題與 README) |

## 快速開始

### 場景一:單次任務

1. 貼入 A 組三件套(或依裁剪順序的精簡版)。
2. 貼任務描述,要求執行模型先判定原型並完成「規劃輸出模板」。
3. 追加該原型的 ANTIPATTERNS 節+EXEMPLAR few-shot。
4. 交付時要求附:驗收逐條結果+R1-R8 自評表+已驗證/未驗證清單。

### 場景二:新專案

1. 貼入 A 組三件套+`bootstrap/BOOTSTRAP_PROMPT.md` 的啟動指令。
2. 貼專案描述,回答執行模型的一次性澄清提問。
3. 分兩批審閱生成的文件(先 SPEC,後 tasks/ADR/CHECKLIST/verify.sh/CLAUDE.md)。
4. 明確同意後,實作依生成的 CLAUDE.md 固定工作流進行。

### 場景三:定期校準

1. 每月(或模型/協議更新後)從 `evals/` 抽 2-3 題。
2. 乾淨對話測基線,加載 harness 再測增益;用 GENERAL_RUBRIC 的 Grader Prompt 判卷。
3. 低分維度依 `evals/README.md` 的回補對照表補材料;連續低分則把要求寫進 CLAUDE.md 固定工作流。

## 維護原則

- 共用詞彙不可漂移:八階段名稱、【澄清】~【自審】段落標籤、R1-R8 維度 ID 與中文名、AP-{前綴}-{NN} 反模式 ID、六原型 slug——任何新增文件必須沿用。
- 實戰中發現新的失手模式 → 先補 `ANTIPATTERNS.md` 條目,再視需要在對應 EXEMPLAR 補「◆ 為什麼這樣做」註解,最後在 `evals/` 換上針對它的陷阱題——規則、示範、評測三處對齊,一個坑才算真正填掉。
