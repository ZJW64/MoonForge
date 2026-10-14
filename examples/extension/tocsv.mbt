// 第三方扩展示例：给 MoonForge 加一条**完全独立于其源码**的规则。
//
// 这里扮演一个"下游使用者"：他要为自家 trait 派生实现，于是
//
//   1. 定义目标 trait（`ToCsv`）与标记 trait（`DeriveToCsv`）；
//   2. 定义一个类型并 `pub impl @forge.DeriveRule for ToCsvRule with ...`；
//   3. 把自己的规则与内置规则合并，交给 `@forge.generate(...)`。
//
// 全程**没有改动 moonforge 的任何一行代码**，也没有往它的注册表里塞东西。
// 这就是"规则数量可以增长"的实际含义：工具的默认规则集只是起点，
// 扩展不需要成为工具的一部分。
//
// 用例见同目录 `tocsv_wbtest.mbt`。

///|
/// 目标 trait：把值渲染成一行 CSV。
pub(open) trait ToCsv {
  fn to_csv(Self) -> String
}

///|
/// 标记 trait：声明"为这个类型派生 ToCsv"。
///
/// 与 `moonforge/derive` 里的标记 trait 形状一致 —— 空 impl 在 MoonBit 里
/// 是语法错误，所以标记 trait 必须带一个方法，由请求方写空体。
pub(open) trait DeriveToCsv {
  fn requested(Self) -> Unit
}

///|
/// 规则类型。第三方规则与内置规则在类型上没有任何区别。
pub struct ToCsvRule {}

///|
pub impl @forge.DeriveRule for ToCsvRule with fn head(_self) -> @forge.RuleHead {
  {
    key: "to_csv",
    marker: "DeriveToCsv",
    trait_name: "ToCsv",
    description: "把 struct 的 String 字段渲染成一行 CSV（第三方规则示例）",
  }
}

///|
pub impl @forge.DeriveRule for ToCsvRule with fn generate(_self, td) -> @forge.Fragment? {
  if !td.has_named_fields() {
    return None
  }
  let cells : Array[String] = []
  let notes : Array[String] = []
  for f in td.fields {
    if f.ty == "String" {
      cells.push("self." + f.name)
    } else {
      notes.push(
        "// moonforge: 跳过 " +
        td.name +
        "." +
        f.name +
        " 的 to_csv（类型 " +
        f.ty +
        " 不是 String）\n",
      )
    }
  }
  let b = StringBuilder()
  // 不带返回类型：由 `ToCsv` 的声明决定，理由见 `Fragment::impl_body` 的契约说明。
  b.write_string("fn to_csv(self) {\n")
  b.write_string("  [" + cells.join(", ") + "].join(\",\")\n")
  b.write_string("}\n")
  Some({ notes, impl_body: b.to_string(), })
}

///|
/// 把内置规则与第三方规则合并 —— 这就是「可扩展」的实际操作。
///
/// 反过来也成立：调用方可以**只**传自己的规则，或只挑内置规则里的两条。
/// 规则集合是显式传入的值，而不是写死在工具内部的常量。
pub fn rules_with_extension() -> Array[&@forge.DeriveRule] {
  let out : Array[&@forge.DeriveRule] = []
  for r in @rules.all() {
    out.push(r)
  }
  out.push(ToCsvRule::{ } as &@forge.DeriveRule)
  out
}

///|
/// 用扩展后的规则集处理一份源码。
pub fn generate_with_extension(
  source_name : String,
  src : String,
) -> @forge.GenOutcome {
  @forge.generate(
    source_name,
    src,
    rules_with_extension(),
    @forge.MOONFORGE_VERSION,
  )
}

///|
/// 演示用的真实类型：手写的 impl 与生成物形状**完全一致**（见测试断言），
/// 因此"生成物能编译"这件事有独立证据，而不是靠工具自说自话。
pub(all) struct Sample {
  host : String
  port : Int
} derive(Eq, Debug)

///|
pub impl ToCsv for Sample with fn to_csv(self) {
  [self.host].join(",")
}
