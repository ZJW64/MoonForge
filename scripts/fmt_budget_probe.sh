#!/usr/bin/env bash
# 列宽预算的"实测发生器"：用真实 moonfmt 把 `FMT_WIDTH_BUDGET`（见 codegen.mbt）钉住。
#
#   bash scripts/fmt_budget_probe.sh
#
# 为什么需要它：生成物是提交进仓库的，用户迟早会跑 `moon fmt`。生成器写出的字节
# 必须与格式化器一致，否则 `check` 永久报漂移，而且 `gen` 也治不好（它照旧写单行版）。
# "fmt 大概 80 列"这种猜测不能用 —— 换一次工具链就可能变。所以这里现场量一遍：
# 构造预算两侧各两条 impl 头，交给真实 moonfmt，再断言
#   * 预算内（<= BUDGET）的行逐字节保持
#   * 超预算（> BUDGET）的行被折开
# 量不到预期就非零退出，绝不"安静地跳过"。
set -euo pipefail

cd "$(dirname "$0")/.."

MOON="${MOON:-moon}"
BUDGET="${BUDGET:-82}"

MOONFMT="${MOONFMT:-}"
if [ -z "$MOONFMT" ]; then
  # 与 moon 同目录 —— 工具链是同一次安装发出来的，这样找最稳。
  MOONFMT="$(dirname "$(command -v "$MOON")")/moonfmt"
fi

if [ ! -x "$MOONFMT" ]; then
  echo "SKIP: 找不到 moonfmt（$MOONFMT）"
  exit 0
fi

work="_build/fmt-budget-probe"
rm -rf "$work"
mkdir -p "$work"

# 用生成器**真正写出来的**形状做探针：`pub impl <前缀>.<Trait> for <类型> with fn <签名> {`
# （不带返回类型 —— 见 Fragment::impl_body 的契约）。类型名用 T 填充到目标列数。
prefix='pub impl @derive.FieldNames for '
tail=' with fn field_names(_self) {'

awk -v pre="$prefix" -v post="$tail" -v budget="$BUDGET" '
BEGIN {
  for (d = -1; d <= 2; d++) {
    n = (budget + d) - length(pre) - length(post)
    name = ""
    for (i = 0; i < n; i++) name = name "T"
    line = pre name post
    print "// PROBE-LEN " length(line)
    print "///|"
    print line
    print "  []"
    print "}"
    print ""
  }
}' > "$work/probe.mbt"

cp "$work/probe.mbt" "$work/before.mbt"
"$MOONFMT" -w "$work/probe.mbt"

# 逐条比对：预算内的行必须逐字节不变，超预算的行必须被折开（变短）。
awk -v budget="$BUDGET" '
FNR == NR {
  if ($0 ~ /^\/\/ PROBE-LEN /) { want[++k] = $3 }
  next
}
$0 ~ /^pub impl / { got[++m] = length($0) }
END {
  bad = 0
  for (i = 1; i <= k; i++) {
    if (want[i] <= budget) {
      if (got[i] != want[i]) {
        printf "FAIL: %d 列在预算内，应当逐字节保持，实际变成 %d 列\n", want[i], got[i]
        bad = 1
      }
    } else if (got[i] >= want[i]) {
      printf "FAIL: %d 列超过预算 %d，应当被折开，实际仍是 %d 列\n", want[i], budget, got[i]
      bad = 1
    }
  }
  if (k != m) {
    printf "FAIL: 探测数量不一致（输入 %d，输出 %d）\n", k, m
    bad = 1
  }
  if (k == 0) {
    print "FAIL: 没有生成任何探针，本脚本没有测到目标行为"
    bad = 1
  }
  if (bad) { exit 1 }
  printf "OK: 列宽预算 %d 实测成立（%d 条里 %d 条折开）\n", budget, k, m
}
' "$work/before.mbt" "$work/probe.mbt"

# 预算的另一个方向也要有意义：低于预算太多时不该折行（否则 BUDGET 可以随便写小）。
awk -v pre="$prefix" -v post="$tail" '
BEGIN {
  name = ""
  n = 60 - length(pre) - length(post)
  for (i = 0; i < n; i++) name = name "T"
  print "///|"
  print pre name post
  print "  []"
  print "}"
}' > "$work/short.mbt"
cp "$work/short.mbt" "$work/short-before.mbt"
"$MOONFMT" -w "$work/short.mbt"
if ! cmp -s "$work/short-before.mbt" "$work/short.mbt"; then
  echo "FAIL: 明显短于预算的 impl 头也被折行了，说明折行阈值不是按整行宽度算的"
  exit 1
fi

echo "OK: 预算内不折行、超预算折开，两个方向都成立"
