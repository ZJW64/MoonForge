#!/usr/bin/env bash
# MoonForge 端到端校验（本地一条命令复现 CI 的全部检查）。
#
#   bash scripts/e2e.sh
#
# 四个阶段：
#   1. 漂移检查：仓库里已提交的生成物必须与当前源文件一致
#   2. 测试：词法 / 语法 / 规则 / 金样 / 幂等 / 使用生成代码的端到端测试
#   3. 编译检查：真实编译生成出来的代码（这一步才是“生成代码正确”的证据）
#   4. 负例：故意改动源文件后，check 必须返回非零（证明漂移真的会被拦下）
set -euo pipefail

cd "$(dirname "$0")/.."
MOON="${MOON:-moon}"

echo "== 1/4 漂移检查：已提交的生成物与源文件一致"
"$MOON" run cmd/main -- check examples

echo
echo "== 2/4 运行测试"
"$MOON" test --target js

echo
echo "== 3/4 编译检查（含自动生成的代码）"
"$MOON" check

echo
echo "== 4/4 负例：源文件改动后 check 必须失败"
backup="$(mktemp)"
cp examples/models.mbt "$backup"
restore() { cp "$backup" examples/models.mbt; rm -f "$backup"; }
trap restore EXIT

printf '\n///\n/// @derive(field_names)\nstruct DriftProbe {\n  k : String\n}\n' >> examples/models.mbt

if "$MOON" run cmd/main -- check examples >/dev/null 2>&1; then
  echo "FAIL: 漂移未被检出（check 返回了 0）"
  exit 1
fi

echo "OK: 漂移被正确检出，check 返回非零"
echo
echo "全部端到端校验通过。"
