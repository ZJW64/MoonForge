// 规则 diff：为类型生成 `impl Diff`。
//
// 逐字段展开比较，返回**发生变化的字段名**（而不是完整结构 diff），
// 这样输出稳定、易断言，也便于上层做审计日志 / 变更追踪。
//
// 前置条件：字段类型需实现 `Eq`（`!=` 可用）。README 中已写明；
// 若不满足，`moon check` 会直接在生成物上暴露出来 ——
// 生成物随仓库提交、参与真实编译，正确性由编译器裁决。

///|
/// 规则类型。
pub struct DiffRule {}

///|
pub impl @forge.DeriveRule for DiffRule with fn head(_self) -> @forge.RuleHead {
  {
    key: "diff",
    marker: "DeriveDiff",
    trait_name: "Diff",
    description: "为 struct 实现 Diff::diff，返回发生变化的字段名（字段类型需实现 Eq）",
  }
}

///|
pub impl @forge.DeriveRule for DiffRule with fn generate(_self, input) -> @forge.Fragment? {
  if !input.has_named_fields() {
    return None
  }
  let b = StringBuilder()
  // 不带返回类型：由 trait 声明决定，理由见 `Fragment::impl_body` 的契约说明。
  b.write_string("fn diff(self, other) {\n")
  b.write_string("  let changed : Array[String] = []\n")
  for f in input.fields {
    b.write_string("  if self." + f.name + " != other." + f.name + " {\n")
    b.write_string("    changed.push(\"" + f.name + "\")\n")
    b.write_string("  }\n")
  }
  b.write_string("  changed\n")
  b.write_string("}\n")
  Some({ notes: [], impl_body: b.to_string(), })
}
