// 规则 to_pairs：为类型生成 `impl ToPairs`。
//
// 场景：把结构体摊平成"字段名 → 字段值"的键值对，交给表单渲染、日志、审计
// 或喂给只认字符串的接口。相比 field_names（只有名字），它带上了值；
// 相比 Debug / Show（输出一整行），它的形状是结构化的、可逐项消费的。
//
// 安全边界与 validate 同一套纪律：**只对 `String` 字段生效**。
// 其他类型怎么变成字符串是语义问题（Int 要十进制还是千分位？枚举要不要
// 本地化？嵌套结构怎么展开？），工具没有资格替用户决定。硬塞一个
// `@debug.to_string(...)` 会生成编译不过的代码（字段类型未必实现 Debug），
// 所以这里一律跳过，并在生成文件里留下说明行 —— "为什么不生成"同样是信息。

///|
/// 规则类型。
pub struct ToPairsRule {}

///|
pub impl @forge.DeriveRule for ToPairsRule with fn head(_self) -> @forge.RuleHead {
  {
    key: "to_pairs",
    marker: "DeriveToPairs",
    trait_name: "ToPairs",
    description: "为 struct 实现 ToPairs::to_pairs，只包含 String 字段（其余字段跳过并留说明行）",
  }
}

///|
pub impl @forge.DeriveRule for ToPairsRule with fn generate(_self, td) -> @forge.Fragment? {
  if !td.has_named_fields() {
    return None
  }
  let pairs : Array[String] = []
  let notes : Array[String] = []
  for f in td.fields {
    if f.ty == "String" {
      pairs.push("(\"" + f.name + "\", self." + f.name + ")")
    } else {
      notes.push(
        "// moonforge: 跳过 " +
        td.name +
        "." +
        f.name +
        " 的 to_pairs（类型 " +
        f.ty +
        " 不是 String；如何转成字符串由使用者决定）\n",
      )
    }
  }
  let b = StringBuilder()
  // 不带返回类型：由 trait 声明决定，理由见 `Fragment::impl_body` 的契约说明。
  b.write_string("fn to_pairs(self) {\n")
  b.write_string("  [" + pairs.join(", ") + "]\n")
  b.write_string("}\n")
  Some({ notes, impl_body: b.to_string(), })
}
