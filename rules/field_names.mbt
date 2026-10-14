// 规则 field_names：为类型生成 `impl FieldNames`。
//
// 这是最简单的一条规则，作用是打通「解析 → IR → 规则 → 生成」的完整链路，
// 并在最少的语义假设下给出可编译的输出。
//
// 规则本身只是一段逻辑：它不认识源码语法，也不需要认识 —— 输入是 IR
// （`@forge.TypeDef`），输出是一段 `impl` 的成员文本。

///|
/// 规则类型。规则以「实现了 `DeriveRule` 的类型」的形式存在，
/// 因此第三方可以照抄这个形状，在自己的包里加一条规则。
pub struct FieldNamesRule {}

///|
pub impl @forge.DeriveRule for FieldNamesRule with fn head(_self) -> @forge.RuleHead {
  {
    key: "field_names",
    marker: "DeriveFieldNames",
    trait_name: "FieldNames",
    description: "为 struct 实现 FieldNames::field_names，顺序与字段声明一致",
  }
}

///|
pub impl @forge.DeriveRule for FieldNamesRule with fn generate(_self, td) -> @forge.Fragment? {
  if !td.has_named_fields() {
    return None
  }
  let items : Array[String] = []
  for f in td.fields {
    items.push("\"" + f.name + "\"")
  }
  let b = StringBuilder()
  // 不带返回类型：由 trait 声明决定，理由见 `Fragment::impl_body` 的契约说明。
  b.write_string("fn field_names(_self) {\n")
  b.write_string("  [" + items.join(", ") + "]\n")
  b.write_string("}\n")
  Some({ notes: [], impl_body: b.to_string(), })
}
