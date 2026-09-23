#!/usr/bin/env bash
# MoonForge 端到端校验（本地一条命令复现 CI 的全部检查）。
#
#   bash scripts/e2e.sh
#
# 五个阶段：
#   1. 漂移检查：仓库里已提交的生成物必须与当前源文件一致
#   2. 测试：词法 / 语法 / 规则 / 金样 / 幂等 / 使用生成代码的端到端测试
#   3. 编译检查：真实编译生成出来的代码（这一步才是“生成代码正确”的证据）
#   4. 格式化稳定性：跑过 `moon fmt` 之后生成物依然无漂移
#      —— 生成物是提交进仓库的，用户迟早会格式化；如果生成器的字节输出与
#         moonfmt 不一致，格式化一次就会让 check 永久报漂移且 gen 修不好。
#   5. 漂移闭环（在 _build 下的副本上做，不碰仓库里的任何文件）：
#      改源码 → check 必须给退出码 1 → gen → check 必须回到 0
set -euo pipefail

cd "$(dirname "$0")/.."
MOON="${MOON:-moon}"

echo "== 1/5 漂移检查：已提交的生成物与源文件一致"
"$MOON" run cmd/main -- check examples

echo
echo "== 2/5 运行测试"
"$MOON" test --target js

echo
echo "== 3/5 编译检查（含自动生成的代码）"
"$MOON" check

echo
echo "== 4/5 格式化稳定性：moon fmt 之后生成物仍与生成结果一致"
"$MOON" fmt
"$MOON" run cmd/main -- check examples

echo
echo "== 5/5 漂移闭环：改源码 → check=1 → gen → check=0"
# 全程在 _build 下的副本上进行：即使中途失败也不会把仓库弄脏，
# 因此不需要“备份 + 还原”这类容易在异常路径上失效的动作。
probe="_build/e2e-probe"
rm -rf "$probe"
mkdir -p "$probe"
cp examples/models.mbt "$probe/probe.mbt"

printf '\n///\n/// @derive(field_names)\nstruct DriftProbe {\n  k : String\n}\n' >> "$probe/probe.mbt"

set +e
"$MOON" run cmd/main -- check "$probe" >/dev/null 2>&1
code=$?
set -e
if [ "$code" -ne 1 ]; then
  echo "FAIL: 漂移未被检出，check 退出码为 $code（约定应为 1）"
  exit 1
fi
echo "OK: 漂移被正确检出，check 退出码为 1"

"$MOON" run cmd/main -- gen "$probe"
"$MOON" run cmd/main -- check "$probe" >/dev/null
echo "OK: gen 之后 check 回到 0（工作流闭环）"

echo
echo "全部端到端校验通过。"
