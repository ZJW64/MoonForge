// 规则 diff：生成 `T::diff(self, other) -> Array[String]`。
//
// 逐字段展开比较，返回**发生变化的字段名**（而不是完整结构 diff），
// 这样输出稳定、易断言，也便于上层做审计日志 / 变更追踪。
//
// 前置条件：字段类型需实现 `Eq`（`!=` 可用）。README 中已写明；
// 若不满足，`moonforge check` 会让漂移/编译问题在 CI 阶段暴露。

///|
pub fn diff() -> @forge.Rule {
  {
    name: "diff",
    description: "为 struct 生成 T::diff(self, other) -> Array[String]，返回发生变化的字段名（字段类型需实现 Eq）",
    gen: fn(td : @forge.TypeDef) -> String? {
      if !td.has_named_fields() {
        return None
      }
      let b = StringBuilder()
      b.write_string("///|\n")
      b.write_string(
        "pub fn " +
        td.name +
        "::diff(self : " +
        td.name +
        ", other : " +
        td.name +
        ") -> Array[String] {\n",
      )
      b.write_string("  let changed : Array[String] = []\n")
      for f in td.fields {
        b.write_string("  if self." + f.name + " != other." + f.name + " {\n")
        b.write_string("    changed.push(\"" + f.name + "\")\n")
        b.write_string("  }\n")
      }
      b.write_string("  changed\n")
      b.write_string("}\n")
      Some(b.to_string())
    },
  }
}
