// 示例：MoonForge 的输入长这样 —— 就是普通的 MoonBit 代码，
// 派生需求写在 doc comment 的 `@derive(...)` 里，没有引入任何新语法。
//
// 生成物是同目录的 `models_derive_gen.mbt`，由
//   moon run cmd/main -- gen examples
// 产出。该文件随仓库提交，因此 `moon check` 会真实地编译它 ——
// 生成代码的正确性由编译器裁决，而不是由工具的自我声明裁决。

///|
/// 用户信息。
///
/// @derive(validate, diff, field_names)
pub(all) struct User {
  /// 姓名
  /// @nonempty
  name : String

  /// 年龄
  /// @min(0) @max(150)
  age : Int

  /// 电子邮箱 —— 没有校验注解，因此不会产生任何检查代码
  email : String
} derive(Eq, Debug)

///|
/// 订单。
///
/// `quantity` 上刻意写了 `@nonempty`：它是 Int，不在规则的内建类型白名单内。
/// 规则不会硬塞一个语义可疑的检查，而是跳过，并在生成文件里留下
/// `// moonforge:` 说明行 —— “为什么不生成”同样是要被解释的信息。
///
/// @derive(field_names, validate, diff)
pub(all) struct Order {
  /// 订单号
  /// @nonempty
  id : String

  /// 金额（单位：分）
  /// @positive
  /// @max(10000000)
  amount_cents : Int

  /// 数量
  /// @nonempty
  quantity : Int

  /// 备注
  /// @nonempty
  note : String
} derive(Eq, Debug)

///|
/// 状态枚举。
///
/// 没有 `@derive` 标记 → MoonForge 完全不碰它。
/// 本期三条规则都只支持 struct；若给 enum 加上标记，会得到“不适用”诊断而不是报错。
pub(all) enum Status {
  Pending
  Paid
  Shipped
} derive(Eq, Debug)
