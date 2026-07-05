# EXEMPLAR — 軟體實作(software-implementation)黃金示範

## 本文件目的

本文件是「軟體實作」原型的完整黃金示範:對一個帶有模糊處的真實委託,把 PLANNING.md 八階段的思考全程外顯,產出可跑的程式碼與測試。執行模型(如 Opus)應以本文件的結構與品質為天花板來模仿——不是抄這裡的快取程式碼,而是抄這裡「怎麼想、怎麼分段、怎麼自證」的過程。

## 如何使用本文件

1. 接到任何軟體實作任務時,先讀一遍本文件,再開始你自己的【澄清】。
2. 八個段落標籤(【澄清】…【自審】)與 PLANNING.md 八階段一一對應;你的產出必須含同樣八段,順序不可換。
3. 「◆ 為什麼這樣做」是給你看的後設註解,指出該步在防哪個反模式(AP ID 見 ANTIPATTERNS.md);實戰交付物中不需要輸出這些行。
4. 看完本文件後,對照同目錄的 CRITIQUE.md,看同一題的典型劣質解長什麼樣、差在哪。

---

## 使用者委託(原文)

> 我們有好幾個服務都會重複去撈同樣的設定資料,想請你用 Python 寫一個記憶體快取模組讓大家共用。需求大概是:資料要可以設定過期時間;快取要有大小上限,滿了就把最不常用的丟掉,不要吃爆記憶體。寫好要附測試。之後不同專案都會用,所以麻煩寫得通用、穩一點。

---

## 【澄清】

通讀兩次,標出模糊處:「大小上限」(單位未定)、「最不常用」(LRU 還是 LFU?)、「過期時間」(到期後如何消失?)、「大家共用」(什麼並發模型?)、「通用、穩一點」(模糊詞,需翻譯成可驗證描述)。

**提問**(以下三題命中 PLANNING.md 表 A 第 4 條「多種合理解讀導向完全不同的產出」,禁止以假設代替提問):

```markdown
開工前需要確認 3 件事(都可只回選項字母):
1. 「大小上限」的單位?(位元組計量需要量測物件大小,實作複雜度完全不同)
   A. 項目筆數  B. 記憶體位元組數 —— 建議:A
2. 「最不常用」指哪種淘汰策略?(LRU 淘汰「最久沒被存取的」,LFU 淘汰「累計使用次數最少的」,行為與實作都不同)
   A. LRU  B. LFU —— 建議:A(業界預設,實作簡單且行為可預期)
3. 「大家共用」的並發模型?(多執行緒要加鎖;asyncio 不能用同一種鎖;跨進程共享則 in-memory 方案根本不成立,得改用 Redis 類外部快取)
   A. 單一進程內多執行緒  B. asyncio  C. 多進程共享 —— 建議:A
```

> **示範說明**:實戰中,走到這裡必須真的停下等使用者回覆,不得先動手。本文件是教學示範,以下以「使用者回覆:都用你建議的預設(A / A / A)」繼續。

**已確認**(綜合委託原文與上述回覆):

- 容量以筆數計;淘汰策略為 LRU;使用情境為單一進程內多執行緒。
- 全新模組,無既有程式碼庫(委託未提及任何現有 repo 或檔案,故無「檔案存在性」需要驗證)。

**假設**(可自行假設但必須明示,全部使用 PLANNING.md 標準句式):

- 假設:TTL 以秒為單位,set 時可逐鍵覆寫,未指定時用建構時的 default_ttl,ttl=None 表永不過期;若不符請告知,影響範圍是 set() 介面與對應測試,約 30 分鐘。
- 假設:過期採「讀取時惰性判定」——過期項在被讀到或容量滿時清除,不開背景清理執行緒;過期項在所有公開介面中一律視同不存在;若不符請告知,影響範圍是新增顯式 purge() 或背景執行緒,約半天。
- 假設:get 算「使用」,會刷新 LRU 順序(業界慣例);若不符請告知,影響範圍是 get() 中一行與一個測試。
- 假設:Python 3.9+、模組本體只用標準函式庫、測試用 pytest(業界通行預設);若不符請告知,影響範圍是測試改寫,約 1 小時。
- 假設:「通用、穩一點」翻譯為:零外部依賴、介面有完整 docstring、邊界行為有明確定義與測試——而不是「加更多功能」;若不符請告知,影響範圍是範圍界定需重議。

◆ 為什麼這樣做:三個歧義中猜錯任何一個(例如把 LFU 做成 LRU、把多進程做成多執行緒),整個模組要重寫——這一段整體在防 **AP-SW-01 過早動手**。三題一次問完、附選項與建議預設,使用者一句話就能放行。

## 【重述】

問題:多個服務重複向下游撈相同的設定資料,浪費延遲與下游負載;使用者要的是把重複讀取變成進程內 O(1) 查找(目的),手段是一個帶 TTL 與容量上限的共用快取模組。
原型:software-implementation(SW)。已載入 ANTIPATTERNS.md 的 SW 節,阻斷級條目:AP-SW-01/02/03/04/05/07。
可能誤解點:(1)「共用」若其實指跨進程,in-memory 方案整個不成立——已於澄清確認為多執行緒。(2)「最不常用」字面上更像 LFU——已確認為 LRU。(3)「通用一點」最容易被曲解成「多加功能」——已在假設中把它翻譯成介面品質而非功能數量。

## 【範圍】

目標:
1. `TTLLRUCache` 類別:`set / get / delete / clear / __len__ / __contains__`,逐鍵 TTL,容量上限 + LRU 淘汰,執行緒安全。
2. pytest 測試:基本讀寫、TTL 語意、LRU 淘汰、錯誤輸入、並發冒煙。

非目標(每條附不做的理由):
1. 不做背景清理執行緒——惰性清除已滿足「過期即不可見」語意;背景執行緒引入生命週期管理與更多並發面,成本大於收益。
2. 不做命中率統計與監控介面——未被要求;之後要加不影響現有介面。
3. 不做 memoize 裝飾器——未被要求;可日後包在本類別之外。
4. 不做持久化與跨進程共享——與 in-memory 定位矛盾;跨進程需求應改用 Redis 類方案,另開任務。
5. 不做位元組級記憶體計量——澄清已確認以筆數計。

邊界裁定:docstring 與型別註記納入(可維護性收益高、成本低);效能 benchmark 不納入(委託無明文效能目標;依 DECISION_PROTOCOL 準則 5,不為未量測的差異投入)。

◆ 為什麼這樣做:非目標逐條寫死,防 **AP-SW-06 範圍蔓延**——「通用、穩一點」是最容易被拿來當擴權藉口的字眼,先把它關進非目標清單。

## 【方案取捨】

- 方案 A:`functools.lru_cache` 外包一層 TTL(把時間片混入 key 讓舊值失效)。優點:程式碼最少、全標準庫。缺點:它是函式記憶化裝飾器,不是 KV 快取——無顯式 set/delete;「時間片混入 key」讓過期變成階梯式近似,且過期舊值仍佔容量名額。成本:小。
- 方案 B:`OrderedDict` + `threading.Lock` 手寫單一類別。優點:語意完全可控、零依賴、行數少、每個行為可測。缺點:正確性全由自己負擔(以測試補上)。成本:小。
- 方案 C:引入第三方 `cachetools.TTLCache`。優點:現成、久經使用。缺點:其 TTL 為全快取統一值,逐鍵 TTL 仍要自行擴充;為多專案共用的基礎模組增加一個外部依賴。成本:中。

裁決(依 DECISION_PROTOCOL 第 1 節,逐準則比較):
- 準則 1 正確性:方案 A 無法精確表達「逐鍵 TTL、到期即不可見」——階梯式近似是已知會產生錯誤結果的情境 → **A 在正確性淘汰**。B、C 都能做對(C 需擴充),打平。
- 準則 2 可回復性:B、C 都是純新增模組、可整包替換,打平。
- 準則 3 簡單性:B 零依賴、單檔約 140 行;C 引入依賴之後,逐鍵 TTL 擴充碼還是得寫,總複雜度不低於 B → **B 勝**。

決策紀錄:[取捨] A vs B vs C → 選 B;裁決準則:A 敗於準則 1 正確性,C 敗於準則 3 簡單性;理由:需求語意可用約 140 行標準庫完整表達,引入依賴或近似語意都不划算。

◆ 為什麼這樣做:第一直覺其實是 C(「有現成的幹嘛自己寫」);強制逐準則比較後才看清 C 的核心需求(逐鍵 TTL)還是得自己寫。先枚舉再裁決,防的是 DECISION_PROTOCOL 1.4 所列的「偏好倒灌」;被否決方案各有一句可檢驗的理由,不是稻草人。

## 【分解】

1. 驗證關鍵 API 假設:`OrderedDict.move_to_end` / `popitem(last=False)` 的存在與實際行為(高風險:整個方案 B 架在這兩個呼叫上)。完成定義:最小實驗有真實輸出。依賴:無。
2. 核心類別:建構驗證、set / get。完成定義:模組可 import,基本讀寫行為正確。依賴:1。
3. 其餘介面與邊界:delete / clear / `__len__` / `__contains__`、參數驗證、「過期=不存在」跨介面一致。完成定義:對照邊界清單逐項有著落。依賴:2。
4. 測試:FakeClock 注入、功能 / TTL / 淘汰 / 錯誤輸入 / 並發冒煙。完成定義:pytest 全綠,有真實輸出。依賴:3。
5. 自審與交付說明。完成定義:驗收逐條核對 + R1-R8 自評表 + 反模式對照完成。依賴:4。

◆ 為什麼這樣做:項 1 把「我記得 OrderedDict 有這些方法」變成「我驗證過」,防 **AP-SW-02 幻覺 API**;風險最高的假設排最前,方案不通第一步就知道,不會做完才發現。

## 【驗收定義】

動手前定稿。每條都寫明怎麼驗:

- [ ] 1. `python -m pytest test_ttl_lru_cache.py -q` 全數通過,0 failed。
- [ ] 2. LRU 語意:容量滿時淘汰「最久未被存取」者,且 get 會刷新順序(由 `test_eviction_removes_least_recently_used` 驗證)。
- [ ] 3. TTL 語意:到期前一刻存活、到期瞬間消失;過期項對 get / in / len / delete 一致不可見(由 `test_entry_alive_before_ttl_expired_at_ttl`、`test_expired_entry_invisible_to_len_contains_delete` 驗證)。
- [ ] 4. 逐鍵 TTL 覆寫與 ttl=None 永不過期可用(由 `test_per_key_ttl_overrides_default`、`test_ttl_none_never_expires` 驗證)。
- [ ] 5. 錯誤輸入:非法 max_entries / ttl 拋 ValueError 且訊息含收到的值;不可雜湊 key 拋 TypeError(由三個錯誤輸入測試驗證)。
- [ ] 6. 並發冒煙:8 執行緒 × 500 次混合操作,零例外、結束後 `len(cache) <= max_entries`(由 `test_concurrent_mixed_operations_keep_invariants` 驗證)。
- [ ] 7. 負面條件:僅新增 `ttl_lru_cache.py` 與 `test_ttl_lru_cache.py` 兩檔;模組本體 import 僅標準函式庫。
- [ ] 8. 人工檢核:每個公開方法的 docstring 寫明語意與邊界行為(含「存 None 與 miss 如何區分」)。

## 【執行】

- [x] **項 1:驗證 OrderedDict API**(真實執行輸出):

```text
$ python -c "from collections import OrderedDict; d = OrderedDict(a=1, b=2, c=3); \
  d.move_to_end('a'); print(list(d)); d.popitem(last=False); print(list(d))"
['b', 'c', 'a']
['c', 'a']
```

`move_to_end` 把鍵移到最新端、`popitem(last=False)` 從最舊端彈出——與方案假設一致,繼續。

- [x] **項 2 + 項 3:模組本體** — `ttl_lru_cache.py`(完整內容):

```python
"""執行緒安全、支援逐鍵 TTL 與容量上限(LRU 淘汰)的 in-memory 快取。

語意摘要(完整討論見交付說明):
- 容量以「項目筆數」計,超出時淘汰最久未被存取的項目(get 與 set 都算存取)。
- TTL 以秒計,可逐鍵覆寫;ttl=None 表示永不過期;過期採讀取時惰性判定,
  過期的項目在所有公開介面(get / in / len / delete)中一律視同不存在。
- 執行緒安全:所有公開方法以單一 threading.Lock 保護,適用於單一進程內
  多執行緒共用;不支援多進程共享(見交付說明的非目標)。
- 時間來源預設 time.monotonic(不受系統時鐘回撥影響);可注入替代時鐘以利測試。
"""

import threading
import time
from collections import OrderedDict
from typing import Any, Callable, Optional

_UNSET = object()  # 哨兵值:區分「呼叫端沒傳 ttl」與「明確傳入 ttl=None(永不過期)」


class TTLLRUCache:
    """容量上限 + 逐鍵 TTL 的執行緒安全快取。

    >>> cache = TTLLRUCache(max_entries=2, default_ttl=60)
    >>> cache.set("a", 1)
    >>> cache.get("a")
    1
    """

    def __init__(
        self,
        max_entries: int,
        default_ttl: Optional[float] = None,
        time_func: Callable[[], float] = time.monotonic,
    ) -> None:
        """max_entries:容量上限(筆數,>= 1)。default_ttl:預設存活秒數,None 表永不過期。"""
        # bool 是 int 的子類,必須先排除,否則 max_entries=True 會被當成 1 悄悄通過
        if isinstance(max_entries, bool) or not isinstance(max_entries, int) or max_entries < 1:
            raise ValueError(f"max_entries 必須是 >= 1 的整數,收到:{max_entries!r}")
        if default_ttl is not None and not self._is_valid_ttl(default_ttl):
            raise ValueError(f"default_ttl 必須是 > 0 的秒數或 None,收到:{default_ttl!r}")
        self._max_entries = max_entries
        self._default_ttl = default_ttl
        self._time = time_func
        self._lock = threading.Lock()
        # key -> (value, expires_at);expires_at 為 None 表示永不過期。
        # OrderedDict 的插入順序即 LRU 順序:最左最舊、最右最新。
        self._entries = OrderedDict()

    @staticmethod
    def _is_valid_ttl(ttl: Any) -> bool:
        return isinstance(ttl, (int, float)) and not isinstance(ttl, bool) and ttl > 0

    def set(self, key: Any, value: Any, ttl: Any = _UNSET) -> None:
        """寫入或覆寫一筆。ttl 未傳時用 default_ttl;傳 None 表示此鍵永不過期。

        key 必須可雜湊(不可雜湊時拋 TypeError,沿用 dict 語意);
        value 可為任意值(含 None,見 get 的說明)。
        """
        if ttl is _UNSET:
            ttl = self._default_ttl
        if ttl is not None and not self._is_valid_ttl(ttl):
            raise ValueError(f"ttl 必須是 > 0 的秒數或 None,收到:{ttl!r}")
        with self._lock:
            expires_at = None if ttl is None else self._time() + ttl
            if key in self._entries:  # 覆寫:先移除舊項,重插後同時刷新 LRU 位置
                del self._entries[key]
            elif len(self._entries) >= self._max_entries:
                self._evict_one_locked()
            self._entries[key] = (value, expires_at)

    def get(self, key: Any, default: Any = None) -> Any:
        """讀取;不存在或已過期時回傳 default。命中會刷新該鍵的 LRU 順序。

        注意:value 本身可以是 None。需要區分「miss」與「存了 None」時,
        請傳入自訂哨兵物件作為 default,或先用 `key in cache` 判斷。
        """
        with self._lock:
            entry = self._entries.get(key)
            if entry is None:
                return default
            value, expires_at = entry
            if expires_at is not None and expires_at <= self._time():
                del self._entries[key]  # 惰性清除:過期即不存在
                return default
            self._entries.move_to_end(key)  # 刷新 LRU:此鍵成為最新
            return value

    def delete(self, key: Any) -> bool:
        """刪除一筆;回傳該鍵是否真的存在(且未過期)。刪除不存在的鍵不是錯誤。"""
        with self._lock:
            entry = self._entries.pop(key, None)
            if entry is None:
                return False
            _, expires_at = entry
            # 已過期的項目視同不存在:仍移除,但回報 False,與 get / len 語意一致
            return expires_at is None or expires_at > self._time()

    def clear(self) -> None:
        """清空全部項目。"""
        with self._lock:
            self._entries.clear()

    def __len__(self) -> int:
        """目前存活(未過期)項目數;呼叫時順帶清除已過期項。"""
        with self._lock:
            now = self._time()
            expired = [k for k, (_, exp) in self._entries.items() if exp is not None and exp <= now]
            for k in expired:
                del self._entries[k]
            return len(self._entries)

    def __contains__(self, key: Any) -> bool:
        """`key in cache`:存在且未過期才為 True。不刷新 LRU 順序、不清除過期項。"""
        with self._lock:
            entry = self._entries.get(key)
            if entry is None:
                return False
            _, expires_at = entry
            return expires_at is None or expires_at > self._time()

    def _evict_one_locked(self) -> None:
        """騰出一格:優先淘汰任一已過期項;無過期項時淘汰 LRU 端(最久未用)。

        呼叫端必須已持有 self._lock。掃描最壞 O(n),對本模組的目標規模
        (數千筆設定資料)可接受;取捨理由見交付說明的已知限制。
        """
        now = self._time()
        expired_key = _UNSET
        for key, (_, expires_at) in self._entries.items():
            if expires_at is not None and expires_at <= now:
                expired_key = key
                break
        if expired_key is not _UNSET:
            del self._entries[expired_key]
        else:
            self._entries.popitem(last=False)
```

◆ 為什麼這樣做:每個 ValueError 訊息都帶「收到的值」(`{...!r}`),失敗時呼叫端立刻知道錯在哪,防 **AP-SW-05 忽略錯誤處理** 中「錯誤訊息不含上下文」的形態;只驗證、上拋,絕不 `except: pass`,防 **AP-SW-09 吞掉例外**。

**邊界情境清單**(項 3 完成定義的核對,對應 GENERAL_RUBRIC R4 的 5 分行為):

| 類別 | 情境 | 處置 |
|---|---|---|
| 輸入邊界 | value 為 None | 已處理:可存;docstring 說明用哨兵 default 區分 miss(get docstring;test_stored_none_distinguishable_from_miss) |
| 輸入邊界 | 不可雜湊 key | 已處理:拋 TypeError,沿用 dict 語意(test_unhashable_key_raises_typeerror) |
| 輸入邊界 | max_entries / ttl 非法(0、負、字串、bool) | 已處理:ValueError 含收到的值(兩個 parametrize 測試) |
| 狀態邊界 | 容量 = 1 | 已處理(test_capacity_one) |
| 狀態邊界 | 覆寫既有鍵不得觸發淘汰 | 已處理(test_overwrite_does_not_evict) |
| 時間邊界 | 恰好到期瞬間 | 已處理:expires_at <= now 即過期(test_entry_alive_before_ttl_expired_at_ttl) |
| 並發 | 混合 set/get/delete/clear | 已處理:單一鎖 + 冒煙測試(test_concurrent_mixed_operations_keep_invariants) |
| 並發 | 快取雪崩(多執行緒同時 miss 同鍵、重複回源) | 不處理:回源邏輯不在本模組職責內,後果是短暫重複載入;呼叫端可自行加 per-key 鎖,已列後續建議 |
| 資源 | 單筆 value 過大仍可能吃爆記憶體 | 不處理:容量以筆數計為澄清時確認的決定;後果與緩解已寫入已知限制 |

- [x] **項 4:測試** — `test_ttl_lru_cache.py`(完整內容):

```python
"""TTLLRUCache 的測試。

時間相關測試一律注入 FakeClock,不用 time.sleep:測試快、結果確定,
且能精確測「恰好到期瞬間」的臨界行為。
"""

import threading

import pytest

from ttl_lru_cache import TTLLRUCache

MISS = object()  # 測試用哨兵:區分 miss 與存入的 None


class FakeClock:
    """可手動推進的假時鐘,介面與 time.monotonic 相同(呼叫回傳秒數)。"""

    def __init__(self, start: float = 1000.0) -> None:
        self.now = start

    def __call__(self) -> float:
        return self.now

    def advance(self, seconds: float) -> None:
        self.now += seconds


@pytest.fixture
def clock():
    return FakeClock()


@pytest.fixture
def cache(clock):
    # 容量 3、預設 TTL 60 秒的小快取,方便觸發淘汰
    return TTLLRUCache(max_entries=3, default_ttl=60, time_func=clock)


# ---------- 基本讀寫 ----------

def test_set_then_get_returns_value(cache):
    cache.set("k", "v")
    assert cache.get("k") == "v"


def test_get_missing_key_returns_default(cache):
    assert cache.get("nope") is None
    assert cache.get("nope", default="fallback") == "fallback"


def test_stored_none_distinguishable_from_miss(cache):
    cache.set("k", None)
    assert cache.get("k", default=MISS) is None      # 存的就是 None
    assert cache.get("absent", default=MISS) is MISS  # 真正的 miss


def test_overwrite_updates_value(cache):
    cache.set("k", 1)
    cache.set("k", 2)
    assert cache.get("k") == 2
    assert len(cache) == 1


# ---------- TTL ----------

def test_entry_alive_before_ttl_expired_at_ttl(cache, clock):
    cache.set("k", "v")            # default_ttl = 60
    clock.advance(59.9)
    assert cache.get("k") == "v"   # 到期前最後一刻仍存活
    clock.advance(0.1)             # 恰好抵達過期時刻
    assert cache.get("k", default=MISS) is MISS


def test_per_key_ttl_overrides_default(cache, clock):
    cache.set("short", 1, ttl=5)
    cache.set("long", 2, ttl=600)
    clock.advance(10)
    assert cache.get("short", default=MISS) is MISS
    assert cache.get("long") == 2


def test_ttl_none_never_expires(cache, clock):
    cache.set("forever", 1, ttl=None)
    clock.advance(10 ** 9)
    assert cache.get("forever") == 1


def test_expired_entry_invisible_to_len_contains_delete(cache, clock):
    cache.set("k", "v")
    clock.advance(61)
    assert "k" not in cache
    assert len(cache) == 0
    assert cache.delete("k") is False  # 過期 == 不存在:delete 回報 False


# ---------- 容量與 LRU 淘汰 ----------

def test_eviction_removes_least_recently_used(cache):
    cache.set("a", 1)
    cache.set("b", 2)
    cache.set("c", 3)
    cache.get("a")       # 存取 a:現在最久未用的是 b
    cache.set("d", 4)    # 容量滿,應淘汰 b
    assert cache.get("b", default=MISS) is MISS
    assert cache.get("a") == 1 and cache.get("c") == 3 and cache.get("d") == 4


def test_overwrite_does_not_evict(cache):
    for k in ("a", "b", "c"):
        cache.set(k, 0)
    cache.set("a", 9)    # 覆寫既有鍵不應觸發淘汰
    assert len(cache) == 3


def test_expired_evicted_before_live_entries(cache, clock):
    cache.set("dying", 1, ttl=5)
    cache.set("live1", 2, ttl=600)
    cache.set("live2", 3, ttl=600)
    clock.advance(10)    # dying 已過期
    cache.set("new", 4)  # 容量滿:應優先淘汰過期的 dying,而非 LRU 端的 live1
    assert cache.get("live1") == 2
    assert cache.get("live2") == 3
    assert cache.get("new") == 4


def test_capacity_one(clock):
    tiny = TTLLRUCache(max_entries=1, time_func=clock)
    tiny.set("a", 1)
    tiny.set("b", 2)
    assert tiny.get("a", default=MISS) is MISS
    assert tiny.get("b") == 2


# ---------- 錯誤輸入 ----------

@pytest.mark.parametrize("bad", [0, -1, 2.5, "10", None, True])
def test_invalid_max_entries_rejected(bad):
    with pytest.raises(ValueError):
        TTLLRUCache(max_entries=bad)


@pytest.mark.parametrize("bad", [0, -5, "60", True])
def test_invalid_ttl_rejected(cache, bad):
    with pytest.raises(ValueError):
        cache.set("k", 1, ttl=bad)
    with pytest.raises(ValueError):
        TTLLRUCache(max_entries=3, default_ttl=bad)


def test_unhashable_key_raises_typeerror(cache):
    with pytest.raises(TypeError):
        cache.set(["list", "key"], 1)


def test_delete_and_clear(cache):
    cache.set("k", 1)
    assert cache.delete("k") is True
    assert cache.delete("k") is False  # 已刪:回報 False,不拋錯
    cache.set("a", 1)
    cache.set("b", 2)
    cache.clear()
    assert len(cache) == 0


# ---------- 執行緒安全(冒煙測試)----------

def test_concurrent_mixed_operations_keep_invariants():
    """8 執行緒併發混合 set/get/delete/clear:不得拋例外、容量不變量必須成立。

    注:這是冒煙測試,能抓到明顯的資料結構競態(如迭代中修改),
    但不構成並發正確性的完整證明——此限制已列入交付說明。
    """
    cache = TTLLRUCache(max_entries=32)  # 用真實時鐘;此測試不依賴 TTL
    errors = []

    def worker(tid: int) -> None:
        try:
            for i in range(500):
                key = (tid * 31 + i) % 50  # 製造跨執行緒的鍵碰撞
                cache.set(key, key * 2)
                value = cache.get(key, default=MISS)
                # 同一鍵永遠寫入 key*2:讀到的要嘛是 miss(被淘汰/清空),要嘛是正確值
                assert value is MISS or value == key * 2
                if i % 7 == 0:
                    cache.delete(key)
                if i % 181 == 0:
                    cache.clear()
        except Exception as exc:  # 測試需要蒐集任何執行緒內的失敗
            errors.append(exc)

    threads = [threading.Thread(target=worker, args=(t,)) for t in range(8)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert errors == []
    assert len(cache) <= 32
```

◆ 為什麼這樣做:每個對外方法都有「空 / 極端值 / 非法型別」與失敗情境的測試,防 **AP-SW-03 只走快樂路徑**;注入 FakeClock 而不是 `time.sleep`,讓 TTL 臨界行為可以被「精確到秒」地驗證,同時測試維持毫秒級速度。

**偏離紀錄**(依 PLANNING.md 階段 7 要求):寫測試時發現 `delete()` 初版對「已過期但尚未清除」的項目回傳 True,與【澄清】定下的「過期即不存在」語意矛盾。修正 delete() 為檢查過期後回報 False,並把該情境加入 `test_expired_entry_invisible_to_len_contains_delete`。影響:僅 delete() 一函式與一個測試,無其他波及。

- [x] **項 4 完成證據:真實測試輸出**:

```text
$ python -m pytest test_ttl_lru_cache.py -q
.........................                                                [100%]
25 passed in 0.06s
```

◆ 為什麼這樣做:上面這段輸出是實際執行得到的,不是想像的——宣稱「測試通過」之前必須真的跑過並引用真實輸出,防 **AP-SW-07 沒跑就說完成**。

## 【自審】

**驗收結果**(逐條對照【驗收定義】):

| # | 標準 | 結果 | 證據 |
|---|---|---|---|
| 1 | pytest 全過 | 通過 | `25 passed in 0.06s`(上方真實輸出) |
| 2 | LRU 語意 | 通過 | test_eviction_removes_least_recently_used:get 過的 a 存活,最久未用的 b 被淘汰 |
| 3 | TTL 語意跨介面一致 | 通過 | 到期瞬間消失 + get/in/len/delete 四介面一致兩測試通過 |
| 4 | 逐鍵 TTL / 永不過期 | 通過 | 對應兩測試通過 |
| 5 | 錯誤輸入 | 通過 | 10 個 parametrize 案例 + TypeError 測試通過;錯誤訊息含 `{值!r}` |
| 6 | 並發冒煙 | 通過 | 8 執行緒 × 500 次,errors == [],len <= 32 |
| 7 | 負面條件 | 通過 | 僅兩個新檔;模組 import 僅 threading / time / collections / typing |
| 8 | docstring 檢核 | 通過 | 六個公開方法均有語意與邊界說明(含 None/miss 區分) |

**反模式檢查**(ANTIPATTERNS.md SW 節逐條):AP-SW-01(先澄清後動手)、02(API 已實驗驗證)、03(邊界清單 9 項)、04(全新模組,無既有介面可破壞)、05 / 09(僅拋帶上下文的例外,無吞例外)、07(輸出為真實執行結果)、06 / 12(diff 僅兩個新檔)、08(過期判斷式重複,見 R6 自評)、10(全新專案,遵循 PEP 8 與 pytest 慣例)、11(無硬編碼路徑;時鐘可注入)。阻斷級:零。

**Rubric 自評**(依 GENERAL_RUBRIC.md 自評表格式):

| 維度 | 分數 | 證據(引用產出物具體位置或內容) | 若 <3 的修正動作 |
|---|---|---|---|
| R1 正確性 | 5 | 25 個測試全過且輸出為真實執行結果;LRU / TTL / 臨界時刻行為各有專屬測試佐證 | — |
| R2 完整性 | 5 | 需求對照無空格:過期時間→逐鍵 TTL;大小上限→max_entries+LRU;測試→25 個;通用穩→零依賴+docstring+邊界定義 | — |
| R3 範圍紀律 | 5 | 僅兩個新檔;統計 / 持久化 / 裝飾器等「順便可做」項全數寫入非目標與後續建議,未動手 | — |
| R4 邊界處理 | 4 | 邊界清單 9 項各標「已處理(測試名)/ 不處理(理由與後果)」;未達 5 分原因:並發僅冒煙測試,非窮盡驗證 | — |
| R5 可驗證性 | 5 | 單一指令 `python -m pytest test_ttl_lru_cache.py -q` 可全部重跑;FakeClock 使 TTL 測試確定性重現;附預期輸出 | — |
| R6 簡潔性 | 4 | 單檔單類別、無多餘抽象;弱點:「exp is not None and exp <= now」過期判斷式在四處出現,可抽私有 helper,列入後續建議 | — |
| R7 可維護性 | 4 | 模組 docstring 給出語意摘要;非顯然決定(bool 排除、哨兵、O(n) 掃描)均有註解;弱點:無獨立使用範例文件,僅類別 docstring 內一例 | — |
| R8 誠實度 | 5 | 冒煙測試的證明力如實標註於測試 docstring;delete() 返工寫入偏離紀錄;下方限制清單完整 | — |

全部維度 >= 3,可交付。

**已知限制與未驗證事項**:
1. 執行緒安全僅涵蓋單進程多執行緒(單一鎖);未在自由執行緒(no-GIL)建置上驗證。並發測試為冒煙性質,不是形式化證明。
2. 淘汰時的過期掃描最壞 O(n);在「數千筆設定資料」的目標規模下可忽略,若未來用到百萬鍵等級需改為到期堆(heap)——屬後續任務。
3. 容量以筆數計,單筆巨大 value 仍可能占用大量記憶體(澄清時確認的決定;緩解:呼叫端控制 value 大小)。
4. 未做效能 benchmark(無明文效能目標)。

**後續建議**(範圍外,不動手):(1) 若呼叫端出現快取雪崩,可外加 per-key 鎖的 `get_or_set()`;(2) 抽出過期判斷 helper 消除四處重複;(3) 若需跨進程共享,改評估 Redis 類方案。
