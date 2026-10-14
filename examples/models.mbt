// 示例：MoonForge 的输入长这样 —— 就是普通的 MoonBit 代码。
//
// 派生入口**不是注释约定，也不是工具自造的 DSL**，而是一行真实的 trait impl：
//
//     pub impl @derive.DeriveXxx for <类型> with fn requested(_self) {}
//
// 标记 trait 由 `moonforge/derive` 提供，因此：拼错名字会直接编译不过，
// IDE 能跳转到定义，`grep` 能搜到全部派生点。
//
// 生成物是同目录的 `models_derive_gen.mbt`，由
//   moon run cmd/main -- gen examples
// 产出。该文件随仓库提交，因此 `moon check` 会真实编译它 ——
// 生成代码的正确性由编译器裁决，而不是由工具的自我声明裁决。

///|
/// 用户信息。
///
/// `to_pairs` 只收 `String` 字段：`age` 是 Int，工具不会替用户决定
/// "Int 该怎么变成字符串"，因此跳过并在生成文件里留下说明行。
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
/// 为 User 请求四项派生。四行 impl 的书写顺序就是生成物中四段 impl 的顺序。
pub impl @derive.DeriveValidate for User with fn requested(_self) {

}

///|
pub impl @derive.DeriveDiff for User with fn requested(_self) {

}

///|
pub impl @derive.DeriveFieldNames for User with fn requested(_self) {

}

///|
pub impl @derive.DeriveToPairs for User with fn requested(_self) {

}

///|
/// 订单。
///
/// `quantity` 上刻意写了 `@nonempty`：它是 Int，不在规则的内建类型白名单内。
/// 规则不会硬塞一个语义可疑的检查，而是跳过，并在生成文件里留下
/// `// moonforge:` 说明行 —— "为什么不生成"同样是要被解释的信息。
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
pub impl @derive.DeriveFieldNames for Order with fn requested(_self) {

}

///|
pub impl @derive.DeriveValidate for Order with fn requested(_self) {

}

///|
pub impl @derive.DeriveDiff for Order with fn requested(_self) {

}

///|
/// 状态枚举。
///
/// 没有任何派生标记 → MoonForge 完全不碰它。
/// 本期四条规则都要求"有具名字段的 struct"；若给它加上标记，
/// 会得到"不适用"诊断而不是报错。
pub(all) enum Status {
  Pending
  Paid
  Shipped
} derive(Eq, Debug)

///|
/// 位置参数（元组）结构体。
///
/// 这里刻意给它加上标记：它在类型种类上仍是 struct，但字段没有名字，
/// "按字段名展开"的规则对它没有意义。工具的取舍是**拒绝生成并说清原因**，
/// 而不是生成一个返回空数组的 `field_names` —— 后者语法上说得通、
/// 语义上完全错误，而且编译器不会报错。
/// `moon run cmd/main -- gen examples` 会为它打印三条 `[warn]` 诊断，
/// `explain` 里则显示为 `struct(位置参数)`。
pub(all) struct Point(Int, Int) derive(Eq, Debug)

///|
pub impl @derive.DeriveFieldNames for Point with fn requested(_self) {

}

///|
pub impl @derive.DeriveValidate for Point with fn requested(_self) {

}

///|
pub impl @derive.DeriveDiff for Point with fn requested(_self) {

}
