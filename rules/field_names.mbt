// 规则 field_names：生成 `T::field_names() -> Array[String]`。
//
// 这是最简单的一条规则，作用是打通“解析 → IR → 生成”的完整链路，
// 并在最少的语义假设下给出可编译的输出。

///|
pub fn field_names() -> @forge.Rule {
  {
    name: "field_names",
    description: "为 struct 生成 T::field_names() -> Array[String]，顺序与字段声明一致",
    gen: fn(td : @forge.TypeDef) -> String? {
      if !td.has_named_fields() {
        return None
      }
      let items : Array[String] = []
      for f in td.fields {
        items.push("\"" + f.name + "\"")
      }
      let b = StringBuilder()
      b.write_string("///|\n")
      b.write_string(
        "pub fn " + td.name + "::field_names() -> Array[String] {\n",
      )
      b.write_string("  [" + items.join(", ") + "]\n")
      b.write_string("}\n")
      Some(b.to_string())
    },
  }
}
