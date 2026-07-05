#!/usr/bin/env bash
# verify.sh — 交付前總驗證骨架(claude-harness-universal bootstrap)
#
# 用途:交付前的唯一驗證入口。CLAUDE.md 固定工作流第 5 步要求本腳本全 PASS 才算完成。
# 填寫方式:把各區段函式裡的「未設定」區塊換成本專案的實際指令({{對應指令}} 佔位)。
#   - 已設定的區段:指令失敗(非零退出碼)即整體 FAIL。
#   - 尚未設定的區段:顯示 SKIP,不影響結果——骨架本身可直接執行不報錯。
# 規則:不得為了讓腳本轉綠而刪除或弱化既有檢查(GENERAL_RUBRIC.md R8);
#       新增專案專屬檢查請加進 custom_checks(),不要另開旁路腳本。

set -euo pipefail

PASS_LIST=()
FAIL_LIST=()
SKIP_LIST=()

run_section() {
  # run_section <名稱> <函式名>:執行一個區段並記錄結果
  local name="$1" fn="$2" rc=0
  echo ""
  echo "=== [${name}] ==="
  "$fn" || rc=$?
  if [ "$rc" -eq 0 ]; then
    PASS_LIST+=("$name")
    echo "--- ${name}: PASS"
  elif [ "$rc" -eq 200 ]; then
    SKIP_LIST+=("$name")
    echo "--- ${name}: SKIP(未設定)"
  else
    FAIL_LIST+=("$name")
    echo "--- ${name}: FAIL(退出碼 ${rc})"
  fi
}

lint() {
  # 填寫指引:換成本專案的靜態檢查指令,例如:
  #   ruff check . && ruff format --check .
  #   npm run lint
  # 設定後刪除下面兩行 SKIP。
  echo "lint 未設定,請填入 {{lint 指令}}"
  return 200
}

tests() {
  # 填寫指引:換成本專案的全量測試指令,例如:
  #   pytest tests/ -x
  #   npm test -- --ci
  # 注意:必須是「全量」測試;只跑子集會漏掉「修好一處弄壞三處」。
  echo "test 未設定,請填入 {{測試指令}}"
  return 200
}

build() {
  # 填寫指引:換成本專案的建置指令,例如:
  #   make build
  #   npm run build
  # 純文件/腳本專案無建置步驟時,保留 SKIP 即可。
  echo "build 未設定,請填入 {{建置指令}}"
  return 200
}

custom_checks() {
  # 填寫指引:放本專案專屬的驗收檢查(對應 SPEC 驗收標準中可自動化的條目),例如:
  #   bash scripts/check_no_secrets.sh          # 憑證掃描
  #   grep -rL '^# SPDX' src/ && return 1       # 授權標頭
  #   python scripts/check_data_consistency.py  # 資料一致性
  # 多條檢查逐條列出,任何一條失敗就 return 1。
  echo "custom_checks 未設定,請填入 {{專案專屬檢查}}"
  return 200
}

run_section "lint"          lint
run_section "test"          tests
run_section "build"         build
run_section "custom_checks" custom_checks

echo ""
echo "==================== verify 結果 ===================="
echo "PASS : ${#PASS_LIST[@]}  (${PASS_LIST[*]:-})"
echo "SKIP : ${#SKIP_LIST[@]}  (${SKIP_LIST[*]:-})"
echo "FAIL : ${#FAIL_LIST[@]}  (${FAIL_LIST[*]:-})"

if [ "${#FAIL_LIST[@]}" -gt 0 ]; then
  echo "結論:FAIL — 修復上列區段後重跑;不得弱化檢查換取通過。"
  exit 1
fi

if [ "${#PASS_LIST[@]}" -eq 0 ]; then
  echo "結論:PASS(全部區段皆為 SKIP — 骨架尚未設定;交付前至少應設定 test 區段)"
else
  echo "結論:PASS"
fi
exit 0
