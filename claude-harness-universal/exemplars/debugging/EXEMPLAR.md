# EXEMPLAR — 除錯排錯(debugging)黃金示範

## 本文件目的

本文件是「除錯排錯」原型的完整黃金示範:對一個線索有限、只知道「時間好像對得上」的偶發 502 事故,把 PLANNING.md 八階段外顯成系統化除錯——症狀陳述、含先驗機率的假設表、最便宜優先的鑑別實驗、可開關的因果確認、根因修法與回歸防護。執行模型(如 Opus)應模仿的是這裡「怎麼縮小假設空間、怎麼定罪、怎麼驗證」的過程,而不是這個具體案例的答案。

## 如何使用本文件

1. 接到任何除錯任務時,先讀一遍本文件,再開始你自己的【澄清】。
2. 八個段落標籤(【澄清】…【自審】)與 PLANNING.md 八階段一一對應;你的產出必須含同樣八段,順序不可換。除錯任務的特殊處:修法只能在根因確認後選定,故【執行】中會「回訪【方案取捨】」做第二輪裁決——回訪要明示並留紀錄,不是默默改計畫。
3. 「◆ 為什麼這樣做」是給你看的後設註解,指出該步在防哪個反模式(AP ID 見 ANTIPATTERNS.md);實戰交付物中不需要輸出這些行。
4. 看完本文件後,對照同目錄的 CRITIQUE.md,看同一題的典型劣質解長什麼樣、差在哪。

---

## 使用者委託(原文)

> 我們的 API 服務最近很怪:白天完全正常,但幾乎每天凌晨三點多都會冒出一批 502,行動端的夜間同步一直被客訴。我們懷疑跟資料庫備份有關,因為時間好像對得上,但沒人確定。我們就一台主機,web 跟資料庫都跑在上面。附上手邊有的東西:一張監控圖(我用文字描述)、一段 nginx 的 error log、還有最近一個月的部署紀錄。麻煩幫我們查出原因並修好,不要再半夜被叫醒了。

### 隨委託附上的線索(以下情境、日誌與數據皆為教學用虛構資料)

**線索 1:監控圖(使用者口述)**

- API p99 延遲:平日穩定約 240ms;自 2026-06-13 起,每天 03:01-03:19 飆到 30 秒以上,之後瞬間回落。
- 5xx 數量:平日為 0;同視窗每晚 20-60 筆(該時段總請求約 1,800 筆,即 1-3%)。
- 主機 CPU:凌晨約 15-40%,沒有明顯異常。監控目前沒有磁碟與記憶體面板。

**線索 2:nginx error log 片段(2026-07-04)**

```text
2026/07/04 03:07:41 [error] 1123#1123: *988821 upstream prematurely closed connection while reading response header from upstream, client: 10.20.4.17, server: api.internal.example, request: "GET /api/v1/orders?status=open HTTP/1.1", upstream: "http://127.0.0.1:8000/api/v1/orders?status=open", host: "api.internal.example"
2026/07/04 03:09:02 [error] 1123#1123: *988907 upstream prematurely closed connection while reading response header from upstream, client: 10.20.7.3, server: api.internal.example, request: "POST /api/v1/sync HTTP/1.1", upstream: "http://127.0.0.1:8000/api/v1/sync", host: "api.internal.example"
2026/07/04 03:12:55 [error] 1124#1124: *989161 connect() failed (111: Connection refused) while connecting to upstream, client: 10.20.4.17, server: api.internal.example, request: "GET /api/v1/orders?status=open HTTP/1.1", upstream: "http://127.0.0.1:8000/api/v1/orders?status=open", host: "api.internal.example"
```

**線索 3:近一個月部署紀錄**

| 日期 | 編號 | 內容 |
|---|---|---|
| 2026-06-05 | #479 | app v2.30:訂單查詢加入分頁 |
| 2026-06-10 | #481 | app v2.31:/api/v1/sync 增量同步協定 v2 |
| 2026-06-12 | #482 | 基礎設施:備份目的地由 NFS 改為本機 /var/backups/pg(NFS 叢集汰換) |
| 2026-06-28 | #486 | nginx:keepalive 參數調整(連線數告警後) |

---

## 【澄清】

通讀兩次,標出模糊處:「偶發」(比例多少才算?)、「跟備份有關」(使用者的猜測,不是事實)、「修好」(502 消失?備份也要照常?)、可用的觀測資料與實驗場地未知、正式環境變更授權未知。

**提問**(第 1、2 題命中 PLANNING.md 表 A 第 6 條「需要使用者才有的資訊或權限」,第 3、4 題命中第 2、5 條「不可逆/高風險領域需授權」,禁止以假設代替提問):

```markdown
開工前需要確認 4 件事(都可只回選項字母):
1. 可觀測資料的範圍?(決定有多少零成本證據,直接影響診斷路線)
   A. 有 sysstat/sar 歷史、gunicorn log、PostgreSQL 慢查詢 log  B. 只有 nginx log —— 建議:A(缺什麼請註明)
2. 是否有資料量級接近正式環境的 staging 可自由實驗?(重現實驗的場地;在正式環境做鑑別實驗屬高風險動作,依 DECISION_PROTOCOL 第 2 節不做)
   A. 有  B. 沒有 —— 建議:A
3. 備份最晚必須何時完成?可否接受變慢?(節流/搬移類修法都會拉長備份時間;這是只有你們知道的業務約束)
   A. 06:00 前完成即可,可變慢  B. 有更緊的時限:____ —— 建議:A
4. 修法部署到正式環境的授權流程?今晚是否需要臨時止血?(正式環境變更需明確授權)
   A. 走正常部署流程,不需今晚止血  B. 需要今晚先止血 —— 建議:A
```

> **示範說明**:實戰中,走到這裡必須真的停下等使用者回覆,不得先動手。本文件是教學示範,以下以「使用者回覆:1=A(sar 保留 28 天;PG 已開 log_min_duration_statement=500ms)、2=A(staging 為上週正式資料還原,約九成大小,同機型 8 核 / 16 GB / SATA SSD)、3=A、4=A(希望一週內根治)」繼續。

**已確認**:

- 三份線索已隨委託附上(見上節);單機部署:nginx → gunicorn → PostgreSQL 與備份目的地同在主機 db-web-01。
- 觀測資料齊全;staging 可自由實驗;備份 06:00 前完成即可;正式環境變更走正常部署流程。

**假設**(可自行假設但必須明示,全部使用 PLANNING.md 標準句式):

- 假設:03:00-03:20 的請求主要為行動端夜間同步,約 1.5 rps(依監控圖 1,800 筆 / 20 分換算);若不符請告知,影響範圍是重現實驗的負載參數與驗收 2 的比例閾值。
- 假設:備份腳本與 cron 定義可直接讀取(/etc/cron.d/pg-backup、/usr/local/bin/pg_backup.sh);若不符請告知,影響範圍是改為向你們索取內容,約十分鐘。
- 假設:「偶發 502」量化為視窗內 1-3% 請求失敗(監控口徑);若不符請告知,影響範圍是驗收 2、3 的閾值。

◆ 為什麼這樣做:第 2、3、4 題的答案會改寫整個實驗計畫與修法空間(沒有 staging 就得走純觀察路線;備份時限緊就不能用限速類修法)。先問清楚再動,防的是 **AP-DB-01 未重現先開刀** 的前身:未確認先定罪——「跟備份有關」目前只是使用者的猜測。

## 【重述】

症狀陳述(精確化):單機部署的 API 服務(nginx → gunicorn ×4 → PostgreSQL 同機),自 2026-06-13 起,每日 03:01-03:19 出現 20-60 筆 502(佔視窗請求 1-3%),其餘時段為零;p99 延遲同視窗自 240ms 飆至 30 秒以上。使用者要的目的:根治半夜 502、確保不復發,且備份照常完成;「備份是兇手」只是待驗假設。
原型:debugging(DB)。已載入 ANTIPATTERNS.md 的 DB 節,阻斷級條目:AP-DB-01/02/03/06/07。
可能誤解點:(1) 時間吻合只是相關不是因果——06-28 的 nginx 變更、其他凌晨排程都得同場受審,不能只審備份。(2)「修好」不含「把備份關掉」這種假修復,備份完成是硬約束。(3) p99 峰值「30 秒以上」與 gunicorn 常見預設逾時 30s 可疑地接近——這是線索,不是結論,待證。

## 【範圍】

目標:
1. 找出根因:可用一句話陳述,且有至少兩類獨立證據支持(對應驗收 1)。
2. 以最小變更修復,並在觸發條件下做修復前後對照驗證;備份本身不得被弄壞(驗收 2、3、4、5)。
3. 回歸防護:告警與 runbook,讓復發或修法衍生風險第一時間可見(驗收 6)。
4. 完整除錯紀錄:假設 → 驗證 → 結果,可交接(驗收 7)。

非目標(每條附不做的理由):
1. 不做備份架構重設計(replica / 異機備份)——長期基礎設施決策,超出「一週內解決」的授權;列入建議清單。
2. 不做應用程式碼與資料庫查詢優化——非備份時段 p99 240ms 表現正常,動它是範圍蔓延。
3. 不動 nginx / gunicorn 設定——除非證據指向它們;「順便調大 timeout」正是本原型最典型的症狀修補。
4. 不修備份腳本既有的健壯性缺陷(退出碼不檢查、非原子寫入)——非本次事故成因;混進修復會污染歸因,列入建議清單。

邊界裁定:若選定的修法引入新風險(如限速使備份變慢),該風險的監控配套納入本次範圍——這是修法自身的邊界處理,不是蔓延。

◆ 為什麼這樣做:非目標 3、4 把「順手改」的路預先封死,防 **AP-DB-10 順手重構**——除錯時 diff 裡的每一行都必須能回答「這行跟根因有什麼關係」。

## 【方案取捨】

### 診斷策略(候選與裁決)

- 方案 A:經驗式修補——直接調高 gunicorn / nginx 逾時、把備份換時段,觀察幾天。優點:立刻能動。缺點:未確立因果就改正式環境;逾時調高只是把 502 換成 30 秒以上的卡頓,還讓未來真正 hang 死的 worker 不再被回收。成本:小,但風險高。
- 方案 B:純正式環境觀察——補齊觀測,等每天一次的 03:00 視窗收證據。優點:零變更風險、證據來自真實現場。缺點:每天只有一個 20 分鐘視窗,而「改變因」的鑑別實驗在正式環境屬高風險動作,幾乎不可行,收斂極慢。
- 方案 C:歷史證據先行 + staging 重現——先用已有的 log 與 sar 歷史(零成本)縮小假設空間,再於 staging 以「合成負載 + 手動觸發備份」建立可開關的重現,做單變因鑑別。優點:實驗可任意重跑、變因可控、正式環境零風險。缺點:建置約半天;staging 與正式的差異(資料九成、合成流量)須列入已知限制。

裁決(依 DECISION_PROTOCOL 第 1 節逐準則比較):
- 準則 1 正確性:方案 A 存在已知會產生錯誤結果的情境——若真因不在逾時,502 依舊,且新增「使用者等 5 分鐘」與「真 hang 不被偵測」兩個錯誤行為 → **A 在正確性淘汰**(它同時就是 AP-DB-02 症狀修補加 AP-DB-05 亂槍打鳥)。B、C 皆不動正式環境行為,打平。
- 準則 2 可回復性:B、C 皆零變更,打平。
- 準則 3 簡單性:達成「可鑑別因果」所需成本,B 的迭代週期是 24 小時且受高風險限制,C 是小時級 → **C 勝**;B 的零成本部分(讀既有 log 與 sar)併入 C 作為前置。

決策紀錄:[取捨] A vs B vs C → 選 C(含 B 的零成本前置);裁決準則:A 敗於準則 1 正確性,B 敗於準則 3 簡單性。

### 假設表(含先驗機率;先驗只決定調查順序,不決定結論)

| ID | 根因假設 | 先驗 | 依據(全部來自三份線索) |
|---|---|---|---|
| H1 | 備份對本機磁碟的未節流讀寫造成 I/O 飽和,查詢變慢超過 worker 逾時而被砍 | 0.45 | 起病日 06-13 緊接部署 #482(備份改寫本機磁碟);症狀視窗長度與備份時長量級吻合;p99 峰值 ≈ 30s 疑似逾時值 |
| H2 | 備份程序的 CPU 佔用讓應用飢餓 | 0.10 | 監控 CPU 凌晨僅 15-40%,偏低;但無 per-core 視角,不能直接排除單核打滿 |
| H3 | 記憶體壓力:worker 被 OOM killer 砍 | 0.10 | 「prematurely closed」與 worker 突然死亡相容;但監控無記憶體面板,無從直接排除 |
| H4 | pg_dump 的鎖阻塞線上查詢 | 0.05 | pg_dump 只取 AccessShareLock,僅與 DDL 衝突;應用凌晨無 schema 變更,先驗低 |
| H5 | 同時段另一個排程才是真兇,備份只是共時 | 0.20 | 「時間對得上」只是相關;必須盤點 03:00-03:20 的全部排程 |
| H6 | 06-28 nginx keepalive 調整所致 | 0.05 | 起病 06-13 早於 06-28,理論上可排除;留殘值防部署紀錄日期有誤 |

(先驗合計 0.95,保留 0.05 給未列假設——假設表是開放的,證據可以把新假設加進來。)

### 鑑別實驗排序(最便宜且鑑別力最高者先行)

| # | 實驗 | 成本 | 能鑑別 | 排序理由 |
|---|---|---|---|---|
| E1 | 精讀三份線索:錯誤訊息逐欄解讀、部署紀錄與起病日對齊 | 零(已有資料) | H6,並更新 H1/H5 | 免費證據先用盡 |
| E2 | 既有 log 挖掘:gunicorn、kernel(OOM)、PG 鎖等待與慢查詢、凌晨排程盤點 | 低(唯讀) | H3、H4、H5 | 唯讀零風險,一次可裁決三個假設 |
| E3 | sar 歷史:事發視窗 vs 平日、部署 #482 前 vs 後 | 低(唯讀) | H1 vs H2 | 直接量測瓶頸是 I/O 還是 CPU |
| E4 | staging 重現:合成負載 + 手動觸發備份 | 中(半天) | 存活假設的重現 | 只為收斂後的存活假設付重現成本 |
| E5 | 單變因開關實驗:只改一個變因,看症狀能否開關 | 中 | 因果方向 | 能「開關症狀」才算定罪,相關不算 |

◆ 為什麼這樣做:先驗最高的 H1 也必須走完 E4、E5 才能定罪——排序防 **AP-DB-05 猜測式亂槍打鳥**(每個實驗都寫明「能鑑別哪些假設」,不做不縮小空間的動作),也防把相關當因果。

## 【分解】

1. 保存現場:歸檔 06-08 至 07-04 的 nginx / gunicorn log、sar 檔、備份腳本與 cron、gunicorn 設定至 incident/741/。完成定義:MANIFEST 列出來源路徑與涵蓋區間。依賴:無。
2. E1+E2:時間軸表 + 假設表後驗更新。完成定義:H3/H4/H5/H6 各有一條可引用的裁決證據。依賴:1。
3. E3:sar 三組對照(事發視窗 / 平日同時段 / 部署 #482 前同視窗)。完成定義:數據表。依賴:1(可與 2 並行)。
4. E4:staging 重現(**高風險項:重現失敗則回【方案取捨】改走 B 路線**)。完成定義:重現腳本入庫 + 連續 3 輪皆出現 ≥1% 的 502。依賴:2、3。
5. E5:單變因鑑別(加入唯一變因 → 移除之,觀察症狀開關)。完成定義:開 / 關對照表。依賴:4。
6. 修法選定與實作(回訪【方案取捨】第二輪裁決)。完成定義:diff + 一行決策紀錄。依賴:5。
7. 驗證:staging 全套重跑 + 正式環境部署後首夜觀察。完成定義:兩份真實輸出,對應驗收 2、3、4。依賴:6。
8. 回歸防護與交付:告警規則、runbook、除錯日誌、建議清單。完成定義:驗收 6、7 的對應物齊備。依賴:7。

◆ 為什麼這樣做:項 1 排最前,防 **AP-DB-09 破壞現場**——log 會輪替、sar 檔一個月就被覆寫,今天不歸檔,下週就沒有「修復前」可對照。

## 【驗收定義】

動手前定稿。每條寫明怎麼驗:

- [ ] 1. 根因可用一句話陳述,且有至少兩類獨立證據(系統指標對照、可開關的重現實驗)。
- [ ] 2. staging:未修復時連續 3 輪重現皆出現 ≥1% 的 502;加入唯一修法變因後 3 輪 0 筆 502 且 p99 < 1s;移除該變因 1 輪症狀復現(可開關)。
- [ ] 3. 正式環境:部署後首夜 03:00-03:20 之 502 = 0 且 gunicorn WORKER TIMEOUT = 0(以既有 log 驗);持續觀察至連續 7 夜(至 07-11),首夜先行驗收、7 夜列入追蹤。
- [ ] 4. 備份未被弄壞(負面條件):dump 檔案存在、大小 ≥ 前 7 日平均之 90%、檔尾含 `-- PostgreSQL database dump complete` 標記、於 04:00 前完成。
- [ ] 5. 變更範圍(負面條件):修改僅涉 pg_backup.sh 與告警規則檔兩檔(`git diff --stat` 驗);app 程式碼、nginx、gunicorn、資料庫設定零改動。新增物僅 incident/741/(歸檔、重現腳本、除錯日誌)與 runbook 條目。
- [ ] 6. 告警規則通過 `promtool check rules`,且以 07-03 夜間歷史資料回放證明主告警會觸發。
- [ ] 7. 除錯日誌完整:每個假設都有「驗證方式 / 結果 / 判定」,無憑感覺排除的項目。

## 【執行】

- [x] **項 1:保存現場**(動任何東西之前):

```text
$ mkdir -p incident/741/{logs,sar,config}
$ cp -a /var/log/nginx/error.log* /var/log/nginx/access.log* incident/741/logs/
$ cp -a /var/log/gunicorn/app.log* incident/741/logs/
$ cp -a /var/log/sysstat incident/741/sar/
$ cp -a /usr/local/bin/pg_backup.sh /etc/cron.d/pg-backup /etc/gunicorn/app.conf.py incident/741/config/
```

歸檔涵蓋 2026-06-08 ~ 07-04,清單記於 incident/741/MANIFEST.md。之後所有分析都讀歸檔副本,原始現場只增不減。

- [x] **項 2:E1+E2 — 精讀與時間軸**:

nginx 錯誤訊息逐欄解讀(兩種訊息,鑑別意義不同):
- `upstream prematurely closed connection while reading response header from upstream`:nginx 已連上 127.0.0.1:8000 並送出請求,upstream 在送出回應標頭**之前關閉了連線**。這不是逾時(逾時會記 `upstream timed out (110: ...)`)——典型成因是處理中的程序死亡(被 kill / 崩潰)。
- `connect() failed (111: Connection refused)`:TCP 層被拒——監聽佇列滿或無人監聽;出現在前者數分鐘之後,相容於「worker 全數卡死、accept 停擺、backlog 灌滿」的階段。
- 結論:錯誤原文指向「上游死亡」,不是「nginx 等不夠久」。「調大 nginx timeout」這條路的先驗直接壓到接近零。

```text
$ grep -c 'WORKER TIMEOUT' incident/741/logs/app.log            # 2026-07-04 全日
31
$ grep 'WORKER TIMEOUT' incident/741/logs/app.log | head -2
[2026-07-04 03:01:12 +0000] [612] [CRITICAL] WORKER TIMEOUT (pid:8841)
[2026-07-04 03:02:47 +0000] [612] [CRITICAL] WORKER TIMEOUT (pid:8850)
$ grep -E '^(workers|timeout)' incident/741/config/app.conf.py
workers = 4
timeout = 30
```

31 筆 WORKER TIMEOUT 全落在 03:01-03:19,視窗外為零;`timeout = 30` 與監控 p99 峰值 ≈ 30s 吻合——「worker 卡超過 30 秒 → master 砍掉 → nginx 看到 prematurely closed」機制鏈成立。

```text
$ cat incident/741/config/pg-backup
0 3 * * * postgres /usr/local/bin/pg_backup.sh
$ grep cron.daily /etc/crontab
25 6 * * * root cd / && run-parts --report /etc/cron.daily
$ journalctl -k --since 2026-06-13 | grep -ci 'out of memory'
0
$ grep -c 'still waiting for' incident/741/logs/postgresql-2026-07-0*.log   # log_lock_waits=on
0
$ cat incident/741/config/pg_backup.sh
#!/bin/bash
# 每日 03:00 備份 app_db(/etc/cron.d/pg-backup 觸發)
pg_dump -U backup app_db > /var/backups/pg/app_db_$(date +%F).sql
find /var/backups/pg -name 'app_db_*.sql' -mtime +7 -delete
$ df /var/backups/pg /var/lib/postgresql | awk '{print $1, $NF}'
Filesystem Mounted
/dev/sda1 /
/dev/sda1 /
```

時間軸(2026-07-04):03:00:01 cron 啟動備份 → 03:01:12 首筆 WORKER TIMEOUT → 03:07 起成批 502(prematurely closed)→ 03:12:55 出現 connection refused → 03:18:36 dump 檔完成(mtime)→ 03:19:05 末筆 WORKER TIMEOUT,之後歸零。

假設表更新:**H3 排除**(無 OOM 紀錄);**H4 排除**(鎖等待 0 筆);**H5 排除**(03:00-03:20 唯一排程就是備份;cron.daily 在 06:25);**H6 排除**(起病 06-13 早於 06-28 十五天)。**H1 後驗升至約 0.7**:備份與資料庫確認共用同一顆 /dev/sda1,且 dump 未壓縮、未節流。H2 待 E3 裁決。

◆ 為什麼這樣做:逐欄精讀讓兩種錯誤訊息各自作證,而不是籠統當成「502 = 逾時」——這一步防 **AP-DB-04 不讀錯誤訊息**;四個假設在零成本下裁決,靠的是「先用盡免費證據」的排序。

- [x] **項 3:E3 — sar 三組對照**:

```text
# 事發視窗(2026-07-04,部署 #482 之後)
$ sar -d -f incident/741/sar/sysstat/sa04 -s 02:50:00 -e 03:30:00 --dev=sda
02:50:01  DEV     tps     rkB/s     wkB/s   aqu-sz   await   %util
03:00:01  sda    64.1    1204.9    2210.3     0.08     1.2     6.8
03:10:01  sda  1893.4   97841.6   95210.4    38.55    44.7    99.6
03:20:01  sda  1421.2   71230.8   69981.5    29.12    41.9    98.8
03:30:01  sda    58.7     980.2    1854.7     0.07     1.1     6.1

# 同視窗,部署 #482 之前(2026-06-10,備份仍寫 NFS)
$ sar -d -f incident/741/sar/sysstat/sa10 -s 03:00:00 -e 03:30:00 --dev=sda
03:10:01  sda   711.8   93122.4     310.6     1.92     2.7    57.3
03:20:01  sda   689.2   90874.1     295.8     1.85     2.6    55.9

# CPU 與記憶體(事發視窗,2026-07-04)
$ sar -u -f incident/741/sar/sysstat/sa04 -s 03:00:00 -e 03:20:00
03:10:01  all   %user 11.2   %system 6.3   %iowait 38.4   %idle 43.1
$ sar -r -f incident/741/sar/sysstat/sa04 -s 03:00:00 -e 03:20:00 | awk '{print $1, $3}'
03:10:01  kbavail 9412308
```

解讀:#482 之前,備份時段磁碟只有讀(93 MB/s 讀、0.3 MB/s 寫),util 57%、await 2.7ms,服務無恙;之後讀寫對撞(98+95 MB/s),util 99.6%、await 惡化 16 倍到 44.7ms——這同時回答了「為什麼以前沒事」。CPU %idle 43(**H2 排除**:瓶頸不在 CPU)、可用記憶體 9.4 GB 平穩(再次佐證 H3 排除)。**H1 後驗約 0.9,剩因果確認。**

- [x] **項 4:E4 — staging 重現**(高風險項,先做):

staging:同機型(8 核 / 16 GB / SATA SSD),上週正式資料還原(約九成)。重現腳本(完整,入庫於 incident/741/repro_502.sh):

```bash
#!/usr/bin/env bash
# repro_502.sh — 在 staging 重現備份時段 502(incident #741)
# 用法:./repro_502.sh <持續秒數> <併發數> <輸出檔>
# 輸出:每行「epoch 狀態碼 總耗時秒」;結尾印總數、5xx 數與 p99。
set -euo pipefail
DURATION="${1:?持續秒數}"; CONC="${2:?併發數}"; OUT="${3:?輸出檔}"
: > "$OUT"
END=$(( $(date +%s) + DURATION ))
worker() {
  while [ "$(date +%s)" -lt "$END" ]; do
    curl -s -o /dev/null --max-time 120 \
      -w "$(date +%s) %{http_code} %{time_total}\n" \
      "http://staging-api.internal.example/api/v1/orders?status=open" >> "$OUT" || true
    sleep 1
  done
}
for _ in $(seq "$CONC"); do worker & done
wait
TOTAL=$(wc -l < "$OUT")
ERR=$(awk '$2 >= 500 {n++} END {print n+0}' "$OUT")
P99=$(sort -k3 -n "$OUT" | awk -v n="$TOTAL" 'NR == int(n*0.99) {print $3; exit}')
printf 'requests=%d  5xx=%d (%.1f%%)  p99=%ss\n' "$TOTAL" "$ERR" \
  "$(awk -v e="$ERR" -v t="$TOTAL" 'BEGIN {print (t ? 100*e/t : 0)}')" "$P99"
```

**偏離紀錄**:原計畫以 wrk 產生負載;staging 無外網無法安裝,改用上述 curl 迴圈(影響:僅工具替換,量測口徑——狀態碼與耗時——不變)。負載約 3 rps,略高於正式的 1.5 rps 以縮短重現時間,形態差異列入已知限制。

```text
$ ./repro_502.sh 1500 4 round1.csv          # 輪 1-3:基線,無備份
requests=4713  5xx=0 (0.0%)  p99=0.211s     # 輪 2、3 同量級:0 筆 5xx
$ sudo -u postgres /usr/local/bin/pg_backup.sh &    # 輪 4-6:手動觸發備份(原腳本)
$ ./repro_502.sh 1500 4 round4.csv
requests=2389  5xx=51 (2.1%)  p99=31.207s   # 輪 5:38 筆(1.6%);輪 6:66 筆(2.8%)
```

備份輪吞吐掉一半(4,713 → 2,389 筆)、p99 卡在 31 秒、502 比例 1.6-2.8% 與正式環境口徑一致;staging 的 sar 同步顯示 sda util 99.2%。**重現成立(連續 3 輪)。**

◆ 為什麼這樣做:至此才取得「最小重現步驟」——在此之前不動任何正式環境設定,防 **AP-DB-01 未重現先開刀**;不能重現,就無法證明任何修復。

- [x] **項 5:E5 — 單變因鑑別(可開關才算定罪)**:

唯一變因:在 staging 備份腳本的 pg_dump 之後插入 `pv -q -L <rate>` 限速(其餘一字不動)。先查證工具存在而非憑記憶:`dpkg -s pv` → `Version: 1.6.6-1`(staging 與正式環境皆確認)。

| 輪 | 條件(唯一變因:限速) | 請求數 | 502 | p99 | sda %util |
|---|---|---|---|---|---|
| 7 | `pv -L 80m` | 4,655 | 0 | 1.83s | 88.4 |
| 8 | `pv -L 60m` | 4,691 | 0 | 0.42s | 71.6 |
| 9 | `pv -L 60m` | 4,668 | 0 | 0.45s | 72.1 |
| 10 | 移除 pv(還原原腳本) | 2,412 | 44(1.8%) | 31.4s | 99.3 |

症狀可由單一變因**開(輪 10)關(輪 8、9)**,因果確立。

**根因(一句話)**:部署 #482 把備份寫入移到與 PostgreSQL 資料同一顆磁碟後,未節流的 pg_dump(讀+寫各約 100 MB/s)使 sda 飽和(util ~100%、await 1ms → 45ms),凡觸及磁碟的查詢延遲超過 gunicorn sync worker 的 30 秒逾時而被 master 砍掉,nginx 端呈現 upstream prematurely closed(worker 全卡死時另見 backlog 滿的 connection refused),即偶發 502;「偶發」是因為只有快取未命中的請求受害。

◆ 為什麼這樣做:輪 7-10 每輪只動限速一個變因,防 **AP-DB-03 一次改多個變因**——若同時動了限速與 gunicorn 設定,輪 8 的歸零就無法歸因。

- [x] **項 6:回訪【方案取捨】(第二輪:修法選擇)+ 實作**:

- 修法 A:調高逾時鏈(gunicorn / nginx 至 300s)。
- 修法 B:備份限速 `pv -L 60m`,加耗時記錄(修法自身風險的配套)。
- 修法 C:備份改從 replica / 異機執行。
- 修法 D:加一顆獨立磁碟供備份寫入。

裁決(依 DECISION_PROTOCOL 第 1 節):準則 1 正確性——A 不移除磁碟競爭,查詢照樣慢 30 秒以上,只是把 502 變成使用者端的長時間卡頓,並讓真正 hang 死的 worker 五分鐘才被回收,屬 AP-DB-02 症狀修補 → **A 淘汰**。B、C、D 皆消除競爭,打平。準則 2 可回復性——B 一行可回復且已在 staging 驗證;C、D 涉及基礎設施遷移,回復成本高且超出本週授權 → **B 勝**;C 列入建議清單為長期解。
決策紀錄:[取捨] A/B/C/D → 選 B;A 敗於準則 1,C、D 敗於準則 2;理由:B 已以開關實驗證明消除根因機制,且可一行回復。限速取 60m:磁碟實測上限約 190 MB/s,60 讀 + 60 寫合計 120,為線上查詢保留約 70 MB/s(輪 7 顯示 80m 時 p99 仍達 1.8s,故取 60m)。

修復 diff(正式環境 /usr/local/bin/pg_backup.sh):

```diff
 #!/bin/bash
 # 每日 03:00 備份 app_db(/etc/cron.d/pg-backup 觸發)
-pg_dump -U backup app_db > /var/backups/pg/app_db_$(date +%F).sql
+# 2026-07-05 incident #741:deploy #482 使備份與 PostgreSQL 共用 sda 後,
+# 未節流的 dump(讀+寫各約 100 MB/s)把 %util 打到 99%、await 惡化到 45ms,
+# 線上查詢超過 gunicorn 30s 逾時被砍,產生 502。pv -L 60m 將未壓縮流限速
+# 於 60 MB/s(讀寫合計約 120,磁碟上限約 190,餘裕留給線上查詢)。
+# 限速值的實驗依據與調整程序見 runbook「pg-backup」。
+START_TS=$(date +%s)
+pg_dump -U backup app_db | pv -q -L 60m > /var/backups/pg/app_db_$(date +%F).sql
+logger -t pg_backup "app_db dump finished in $(( $(date +%s) - START_TS ))s"
 find /var/backups/pg -name 'app_db_*.sql' -mtime +7 -delete
```

如實揭露:改為管線後,pg_dump 的退出碼會被管線吞掉;但原腳本本就未檢查退出碼(無 set -e),故未引入新的失效模式——完整修正(pipefail + 原子改名)屬既有缺陷,列建議清單 S1,不混入本次 diff。2026-07-04 16:20 隨部署 #488 上線。

- [x] **項 7:驗證(修復前後、在觸發條件下)**:

staging 全套重跑:輪 11-13(修復版腳本 + 同負載)→ 502 = 0 / 0 / 0,p99 = 0.42 / 0.44 / 0.41s;dump 檔尾含 `-- PostgreSQL database dump complete`,耗時 29 分。

正式環境首夜(2026-07-05):

```text
$ awk '$4 ~ /05\/Jul\/2026:03:0|05\/Jul\/2026:03:1/ && $9 == 502' access.log | wc -l
0
$ grep -c 'WORKER TIMEOUT' /var/log/gunicorn/app.log      # 07-05 03:00-03:20
0
$ journalctl -t pg_backup --since "2026-07-05 03:00"
Jul 05 03:31:42 db-web-01 pg_backup[21873]: app_db dump finished in 1897s
$ ls -lh /var/backups/pg/app_db_2026-07-05.sql | awk '{print $5}'
108G
$ tail -n 2 /var/backups/pg/app_db_2026-07-05.sql | head -1
-- PostgreSQL database dump complete
$ sar -d -s 03:00:00 -e 03:30:00 --dev=sda | awk 'NR==4'
03:10:01  sda   1102.7   61873.4   60110.8    3.41    3.9    71.2
```

首夜:0 筆 502、0 筆 WORKER TIMEOUT;備份 31.6 分完成(108G ≥ 前 7 日平均 110G 之 90%)、檔尾標記完整;磁碟 util 71%、await 3.9ms。

◆ 為什麼這樣做:驗證跑在**症狀原本會出現的條件下**(staging 開備份、正式環境 03:00 視窗),且偶發問題不以單次通過收案——連續 7 夜觀察至 07-11 才關閉(原本每夜必發,7 個乾淨夜的證據力足夠)。這一步同時防 **AP-DB-06 修好不驗證** 與 **AP-DB-08 flaky 當修好**。

- [x] **項 8:回歸防護與交付物**:

告警規則(monitoring/alerts_backup_window.yml,完整):

```yaml
groups:
  - name: incident-741-regression
    rules:
      - alert: Api5xxRateHigh
        expr: sum(rate(nginx_http_requests_total{status=~"5.."}[5m]))
              / sum(rate(nginx_http_requests_total[5m])) > 0.005
        for: 10m
        labels: {severity: page}
        annotations:
          summary: "API 5xx 比率連續 10 分鐘 > 0.5%(incident #741 主症狀)"
          runbook: "runbook.md#pg-backup"
      - alert: PgBackupTooSlow
        expr: time() - app_pg_backup_last_success_timestamp > 86400 * 1.5
              or app_pg_backup_duration_seconds > 5400
        labels: {severity: ticket}
        annotations:
          summary: "備份逾 90 分鐘或超過 1.5 天未成功:資料成長逼近 60 MB/s 限速時窗,重新評估(runbook)"
          runbook: "runbook.md#pg-backup"
```

```text
$ promtool check rules monitoring/alerts_backup_window.yml
SUCCESS: 2 rules found
$ # 以 07-03 夜間資料回放主告警 expr(修復前基線)
$ promtool query instant ... 'sum(rate(nginx_http_requests_total{status=~"5.."}[5m])) / ...' --time 2026-07-03T03:10:00Z
0.021    # > 0.005,會觸發 —— 告警經歷史回放驗證有效
```

runbook 條目(runbook.md#pg-backup,完整):

```markdown
## pg-backup(app_db 每日備份)
- 何時跑:每日 03:00(/etc/cron.d/pg-backup);目前耗時約 32 分(110 GB)。
- 為何限速:備份與資料庫共用 sda;未節流會打滿磁碟造成 502(incident #741,2026-07)。
- 限速值:pv -L 60m(未壓縮流)。依據:磁碟上限約 190 MB/s;60 讀 + 60 寫,餘裕約 70 給線上。
- 若 PgBackupTooSlow 觸發(資料成長):(a) 重跑 incident/741/repro_502.sh 對照實驗後調高限速;(b) 改從 replica 備份(建議 S3)。
- 鐵律:凡修改本備份路徑上任何環節,必須先在 staging 重跑上述對照實驗。
```

除錯日誌(incident/741/DEBUGLOG.md,最終狀態):

| # | 假設 | 驗證方式 | 結果 | 判定 |
|---|---|---|---|---|
| H1 | 備份未節流讀寫使磁碟飽和 → 查詢逾時 → worker 被砍 | sar 對照(項 3)+ 開關實驗(項 4、5) | util 99.6% / await 44.7ms 僅見於備份時段;限速一開 502 歸零、一關復現 | 成立(根因) |
| H2 | 備份 CPU 佔用使應用飢餓 | sar -u(項 3) | %idle 43.1、%iowait 38.4——瓶頸在 I/O | 排除 |
| H3 | OOM killer 砍 worker | journalctl -k + sar -r(項 2、3) | 無 OOM 紀錄;可用記憶體 ≥ 9.4 GB | 排除 |
| H4 | pg_dump 鎖阻塞查詢 | log_lock_waits 紀錄(項 2) | 'still waiting for' 0 筆;pg_dump 僅取 AccessShareLock | 排除 |
| H5 | 其他凌晨排程才是真兇 | 排程盤點(項 2) | 03:00-03:20 唯一排程即備份 | 排除 |
| H6 | 06-28 nginx 調整所致 | 時間軸(項 2) | 起病 06-13 早於 06-28 | 排除 |

建議清單(範圍外,不動手,另開任務):S1 備份腳本 pipefail + 寫入 .tmp 後原子改名 + 退出碼檢查;S2 dump 壓縮(zstd)換約 4 倍空間,需另行量測 CPU 影響;S3 長期改從 replica 備份,徹底解除共用磁碟競爭;S4 監控補磁碟 I/O 面板(本次調查發現監控無磁碟視角)。

◆ 為什麼這樣做:除錯日誌讓已排除的假設帶著證據留下,防 **AP-DB-11 不留除錯紀錄**;S1-S4 只列清單不動手,防 **AP-DB-10 順手重構**——它們混進來會讓「502 消失」無法歸因於單一修法。

## 【自審】

驗收結果(逐條,附證據):
- 1 通過:根因一句話(項 5 末),證據兩類——sar 前後對照(項 3)+ 可開關重現(輪 4-10)。
- 2 通過:輪 4-6 重現(1.6-2.8%)、輪 8-9 歸零(p99 0.42/0.45s)、輪 10 復現(1.8%)。
- 3 **部分通過**:首夜 07-05 通過(0 筆 502、0 筆 WORKER TIMEOUT);連續 7 夜(至 07-11)未完成,已列追蹤(告警 + 07-11 回檢後才關閉事故單)。
- 4 通過:108G(≥ 110G 之 90%)、檔尾標記完整、03:31 完成。
- 5 通過:`git diff --stat` 僅 pg_backup.sh 與 alerts_backup_window.yml;新增物僅 incident/741/ 與 runbook 條目。
- 6 通過:promtool SUCCESS;07-03 回放值 0.021 > 0.005 會觸發。
- 7 通過:除錯日誌 6 個假設全有「驗證方式 / 結果 / 判定」。

Rubric 自評(依 GENERAL_RUBRIC.md 固定格式):

| 維度 | 分數 | 證據(引用產出物具體位置或內容) | 若 <3 的修正動作 |
|---|---|---|---|
| R1 正確性 | 5 | 根因有兩類獨立證據且可開關(項 3、5);錯誤訊息逐欄解讀排除「nginx 逾時」誤診(項 2);修復後首夜實測 0 筆 502(項 7) | — |
| R2 完整性 | 4 | 委託四項(查因、修復、驗證、防復發)各對應驗收 1/2/3/6;驗收 3 的 7 夜部分未完但已列追蹤,非靜默缺漏 | — |
| R3 範圍紀律 | 5 | diff 僅兩檔(驗收 5);S1-S4 全走建議清單而非動手;nginx / gunicorn / app 零改動 | — |
| R4 邊界處理 | 4 | 修法自身風險(備份變慢、資料成長)有告警與 runbook;pv 吞退出碼已聲明;未涵蓋:備份與手動維運作業(VACUUM FULL 等)同時發生的疊加情境,已列入已知限制 | — |
| R5 可驗證性 | 5 | 重現腳本入庫可重跑;每個判定都附指令與輸出;告警以歷史回放驗證會響 | — |
| R6 簡潔性 | 4 | 修復本體為一行管線 + 一行記錄;重現腳本的 p99 計算(sort+awk)偏粗糙,可精簡但不影響口徑 | — |
| R7 可維護性 | 4 | 腳本內註解寫明限速理由與依據;runbook 含調整程序與鐵律;除錯日誌可交接;60m 與 5400s 兩個常數的推導集中在 runbook 而非散落 | — |
| R8 誠實度 | 5 | 7 夜觀察未完成如實標註「部分通過」;staging 差異(資料九成、合成流量 3 rps vs 真實 1.5 rps)與 pv 退出碼問題主動揭露;失敗路線(80m 限速不夠好)留有紀錄 | — |

最弱兩維度:R4(疊加情境未測)、R6(重現腳本可再精簡)。
反模式檢查:AP-DB-01 至 11 逐條過——01 重現於項 4;02 修在機制(移除磁碟競爭)而非症狀(調逾時);03 輪 7-10 單變因;04 兩種錯誤訊息逐欄精讀;05 每輪實驗先寫假設;06 修復前後皆在觸發條件下重跑;07 未動任何測試 / 告警閾值遷就結果;08 偶發問題以開關 + 7 夜追蹤驗證;09 現場先歸檔;10 四項發現全進建議清單;11 除錯日誌完整。**阻斷級殘留:零。**
已知限制:staging 資料為九成量、負載為合成形態;限速值 60m 綁定當前磁碟(換硬體須依 runbook 重測);7 夜觀察 07-11 才到期,事故單保持開啟至該日。
