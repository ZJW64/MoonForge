// moonforge/derive —— 「可派生 trait」与「派生标记 trait」的定义。
//
// 本包不含任何逻辑，只有 trait 声明。它存在是为了让「派生」这件事在 MoonBit
// **语言层面**有名字，而不是靠某个工具自造的注释约定：
//
//   1. 目标 trait（FieldNames / Diff / Validate / ToPairs）
//      —— moonforge 为它们生成 `impl`，业务代码直接消费；
//   2. 标记 trait（DeriveFieldNames / DeriveDiff / ...）
//      —— 用户在自己的源码里写**一行 impl** 表达「我要派生这个」，
//         这就是派生入口。
//
// 为什么标记 trait 必须与目标 trait 分开：
// MoonBit 不允许空的 impl —— `impl T for X {}` 会被解析成 grouped impl 而在
// 语法层就报错（`Invalid grouped impl declarations`）。因此「只声明、不实现」
// 必须落在一个**有方法**的 trait 上。约定如下：
//
//   pub impl @derive.DeriveFieldNames for User with fn requested(_self) {}
//   // ↑ 用户手写：真实 trait 语法，编译期可检查拼写
//   impl @derive.FieldNames for User with fn field_names(self) -> Array[String] { ... }
//   // ↑ moonforge 生成：真正被消费的实现
//
// 两者靠规则里的 `marker` / `trait_name` 两个字段配对（见 rule.mbt）。
// 用户源码里不出现任何注释约定、不出现任何 DSL。

///|
/// 为类型派生 `field_names`：按声明顺序返回具名字段。
pub(open) trait FieldNames {
  fn field_names(Self) -> Array[String]
}

///|
/// 为类型派生 `diff`：逐字段比较，返回发生变化的字段名。
///
/// 前置条件：字段类型需实现 `Eq`（用到 `!=`）。
pub(open) trait Diff {
  fn diff(Self, Self) -> Array[String]
}

///|
/// 为类型派生 `validate`：按字段注解做检查，返回第一条失败原因。
pub(open) trait Validate {
  fn validate(Self) -> Result[Unit, String]
}

///|
/// 为类型派生 `to_pairs`：把结构体摊平成「字段名 → 字段值」的键值对。
pub(open) trait ToPairs {
  fn to_pairs(Self) -> Array[(String, String)]
}

///|
/// 声明「为这个类型派生 FieldNames」。
///
/// 方法体由用户写成空体（`{}`），只为让 impl 合法；
/// 真正的方法实现由 moonforge 生成到同目录的 `*_derive_gen.mbt`。
pub(open) trait DeriveFieldNames {
  fn requested(Self) -> Unit
}

///|
/// 声明「为这个类型派生 Diff」。
pub(open) trait DeriveDiff {
  fn requested(Self) -> Unit
}

///|
/// 声明「为这个类型派生 Validate」。
pub(open) trait DeriveValidate {
  fn requested(Self) -> Unit
}

///|
/// 声明「为这个类型派生 ToPairs」。
pub(open) trait DeriveToPairs {
  fn requested(Self) -> Unit
}
