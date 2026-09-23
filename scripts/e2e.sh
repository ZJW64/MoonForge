#!/usr/bin/env bash
# MoonForge 端到端校验（本地一条命令复现 CI 的全部检查）。
#
#   bash scripts/e2e.sh
#
# 六个阶段：
#   1. 漂移检查：仓库里已提交的生成物必须与当前源文件一致
#   2. 测试：词法 / 语法 / 规则 / 金样 / 幂等 / 使用生成代码的端到端测试
#   3. 编译检查：真实编译生成出来的代码（这一步才是“生成代码正确”的证据）
#   4. 格式化稳定性：跑过 `moon fmt` 之后生成物依然无漂移
#      —— 生成物是提交进仓库的，用户迟早会格式化；如果生成器的字节输出与
#         moonfmt 不一致，格式化一次就会让 check 永久报漂移且 gen 修不好。
#   5. CRLF 容忍：把生成物换成 CRLF（模拟 Windows 上 core.autocrlf=true 的
#      检出结果）之后，check 依然必须通过
#   6. 漂移闭环与退出码契约（在 _build 下的副本上做，不碰仓库里的任何文件）：
#      改源码 → check 必须给退出码 1 → gen → check 必须回到 0；
#      路径不存在 / 不是 .mbt / 目录里没有 .mbt，都必须给退出码 2。
#      最后一个断言防的是"假绿"：路径写错却返回 0，CI 显示通过，其实一个
#      文件都没检查。
set -euo pipefail

cd "$(dirname "$0")/.."
MOON="${MOON:-moon}"

echo "== 1/6 漂移检查：已提交的生成物与源文件一致"
"$MOON" run cmd/main -- check examples

# 位置参数结构体 Point 没有具名字段，任何按字段名展开的规则都不该为它产出代码。
# 修复前它会"借用"下一个声明的字段体，这里把它钉死。
if grep -q "Point::" examples/models_derive_gen.mbt; then
  echo "FAIL: 位置参数结构体 Point 不应该有任何生成方法"
  exit 1
fi
echo "OK: 位置参数结构体没有产出任何生成方法"

echo
echo "== 2/6 运行测试"
"$MOON" test --target js

echo
echo "== 3/6 编译检查（含自动生成的代码）"
"$MOON" check

echo
echo "== 4/6 格式化稳定性：moon fmt 之后生成物仍与生成结果一致"
"$MOON" fmt
"$MOON" run cmd/main -- check examples

echo
echo "== 5/6 CRLF 容忍：生成物被换成 CRLF 后 check 仍须通过"
crlf_dir="_build/e2e-crlf"
rm -rf "$crlf_dir"
mkdir -p "$crlf_dir"
cp examples/models.mbt "$crlf_dir/models.mbt"
"$MOON" run cmd/main -- gen "$crlf_dir" >/dev/null

# 用 POSIX 的 while+printf 转 CRLF，不依赖 GNU/BSD sed 的差异
while IFS= read -r line || [ -n "$line" ]; do
  printf '%s\r\n' "$line"
done < "$crlf_dir/models_derive_gen.mbt" > "$crlf_dir/models_derive_gen.mbt.tmp"
mv "$crlf_dir/models_derive_gen.mbt.tmp" "$crlf_dir/models_derive_gen.mbt"

# 先确认转换真的生效，否则这一阶段会"通过"但什么都没测到
plain_len="$(wc -c < "$crlf_dir/models_derive_gen.mbt" | tr -d ' ')"
stripped_len="$(tr -d '\r' < "$crlf_dir/models_derive_gen.mbt" | wc -c | tr -d ' ')"
if [ "$plain_len" -eq "$stripped_len" ]; then
  echo "FAIL: 生成物里没有 CR，CRLF 转换未生效，本阶段没有测到目标行为"
  exit 1
fi
echo "OK: 生成物已含 CR（$plain_len 字节 vs 去 CR 后 $stripped_len 字节）"

"$MOON" run cmd/main -- check "$crlf_dir" >/dev/null
echo "OK: CRLF 生成物没有被误判成漂移"

echo
echo "== 6/6 漂移闭环与退出码契约"
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

# 路径有误必须是退出码 2，而不是"安静地通过"
expect_code2() {
  set +e
  "$MOON" run cmd/main -- "$@" >/dev/null 2>&1
  local code=$?
  set -e
  if [ "$code" -ne 2 ]; then
    echo "FAIL: '$*' 的退出码为 $code（约定应为 2）"
    exit 1
  fi
}
expect_code2 check "$probe/does-not-exist.mbt"
expect_code2 check "$probe/probe_derive_gen.mbt"
expect_code2 gen README.md
expect_code2 explain "$probe"
echo "OK: 路径不存在 / 非 .mbt / explain 传目录，退出码都是 2"

# gen 必须把"源文件里已经没有 @derive"的残留生成物清理掉，
# 否则 check 会一直报"多余的生成文件"，而照它的提示跑 gen 也修不好。
stale="_build/e2e-stale"
rm -rf "$stale"
mkdir -p "$stale"
cp examples/models.mbt "$stale/models.mbt"
"$MOON" run cmd/main -- gen "$stale" >/dev/null
test -f "$stale/models_derive_gen.mbt" || {
  echo "FAIL: 前置条件不成立，没有生成出 models_derive_gen.mbt"
  exit 1
}
cat > "$stale/models.mbt" <<'MOONFORGE_EOF'
///|
/// 一个不再需要派生代码的类型。
struct Plain {
  a : Int
}
MOONFORGE_EOF
"$MOON" run cmd/main -- gen "$stale" >/dev/null
if [ -f "$stale/models_derive_gen.mbt" ]; then
  echo "FAIL: gen 没有清理残留的生成物"
  exit 1
fi
"$MOON" run cmd/main -- check "$stale" >/dev/null
echo "OK: 去掉 @derive 后 gen 会清理残留生成物，check 随之回到 0"

echo
echo "全部端到端校验通过。"
