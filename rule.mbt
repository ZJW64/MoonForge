// 派生规则的 SPI（扩展点）。
//
// 「可扩展」的落点：**一条规则 = 一个实现了 `DeriveRule` trait 的类型**。
// 规则集合是 `Array[&DeriveRule]`（trait object 数组），因此天然是异构的：
// 内置规则、第三方规则、测试桩可以放进同一个数组，代码生成侧只认 trait 方法。
//
// 第三方扩展的完整做法（**不需要改动 moonforge 的任何源码**）：
//   1. 在自己的包里定义目标 trait 与对应的标记 trait（也可以直接复用
//      `moonforge/derive` 里已有的）；
//   2. 定义一个类型，写 `pub impl @forge.DeriveRule for YourRule with ...`；
//   3. 把自家规则与内置规则合并，交给 `@forge.generate(...)`。
// 仓库里的 `examples/extension/` 就是一个可运行的第三方扩展示例。
//
// 为什么用 trait 而不是"结构体 + 函数字段"：
// 函数字段只能表达"一个函数"，规则的身份（键名、标记名、目标 trait 名）
// 会退化成几个散落的字符串；trait 让身份成为规则**类型**的一部分，
// 由类型检查器保证 `head()` 与 `generate()` 同时存在，第三方也不必猜字段名。
//
// 为什么是 2 个方法而不是 5 个访问器：
// MoonBit 的 `impl ... with` 一个块只能写一个方法，5 个访问器就要 5 个 impl 块，
// 每条规则多出 20 行纯样板。把身份收进 `RuleHead` 记录后，样板降到 2 块，
// 而"身份字段必须齐全"这件事仍由记录类型保证。

///|
/// 规则的静态身份。四个字段都必须给全，否则类型检查不过。
pub(all) struct RuleHead {
  /// 规则键：用于诊断信息与 `list-rules` 展示，例如 `field_names`。
  key : String
  /// 用户在源码里书写的**标记 trait 名**（不含包前缀），例如 `DeriveFieldNames`。
  /// 解析器据此把「请求」归属到本规则。
  marker : String
  /// 生成物要实现的**目标 trait 名**，例如 `FieldNames`。
  trait_name : String
  /// 一句话说明，用于 `list-rules`。
  description : String
}

///|
/// 一条规则为某个类型产出的一段 `impl`。
///
/// 分成两半是必要的：说明行是 `// moonforge: ...` 注释，必须落在 `impl` **之前**
/// 且与 `impl` 之间空一行（`moon fmt` 对「独立注释块 + 紧随其后的 item」的要求；
/// 生成物是提交进仓库的，格式化后必须仍然逐字节稳定）；而成员文本要接在
/// `with` 之后。若合成一整段字符串再去切，就多了一处只靠约定维持的边界。
pub(all) struct Fragment {
  /// 前置说明行，每行自带换行；无跳过项时为空数组。
  notes : Array[String]
  /// `impl ... with` 之后的成员文本（以 `fn` 开头）。
  ///
  /// # 契约：只写 `fn <方法名>(<参数>) {`，**不要抄返回类型**
  ///
  /// 生成的 impl 头长这样：
  ///
  /// ```text
  /// pub impl @derive.Validate for User with fn validate(self) {
  /// ```
  ///
  /// 返回类型不写，由目标 trait 的声明唯一决定（实现本来就必须与 trait 签名一致，
  /// 抄一遍只是重复信息）。**这不是风格偏好，是硬约束**：`moon fmt` 会把长度超过
  /// 82 列的行重新折行（实测 82 列保持、83 列起折），一旦超限就会变成
  ///
  /// ```text
  /// pub impl @derive.Validate for User with fn validate(self) -> Result[
  ///   Unit,
  ///   String,
  /// ] {
  /// ```
  ///
  /// 于是生成物与格式化器不一致 → 用户跑一次 `moon fmt`，`check` 就永久报漂移，
  /// 而且 `gen` 也修不好（它还是会写出单行版）。省掉返回类型后，impl 头从
  /// 83～85 列降到 58～61 列，留出约 20 列的余量给类型名与方法名。
  ///
  /// 因此规则作者只需保证「`fn 方法名(参数)` 这一段 + 类型名」不撑爆那 20 列余量。
  impl_body : String
}

///|
/// 一条派生规则。
pub(open) trait DeriveRule {
  /// 规则的静态身份。
  fn head(Self) -> RuleHead
  /// 生成 `impl` 的内容。
  ///
  /// 返回 `None` 表示「该规则不适用于这个类型」（例如只处理结构体的规则
  /// 遇到枚举），这是**正常结果而不是错误**。
  fn generate(Self, TypeDef) -> Fragment?
}

///|
/// 规则键。
pub fn key_of(r : &DeriveRule) -> String {
  r.head().key
}

///|
/// 标记 trait 名。
pub fn marker_of(r : &DeriveRule) -> String {
  r.head().marker
}

///|
/// 目标 trait 名。
pub fn trait_name_of(r : &DeriveRule) -> String {
  r.head().trait_name
}

///|
/// 一句话说明。
pub fn description_of(r : &DeriveRule) -> String {
  r.head().description
}

///|
/// 按规则键查找。
pub fn find_rule(rules : Array[&DeriveRule], key : String) -> &DeriveRule? {
  for r in rules {
    if key_of(r) == key {
      return Some(r)
    }
  }
  None
}

///|
/// 按**标记 trait 名**查找 —— 解析器只认标记名，这是它唯一的入口。
pub fn find_rule_by_marker(
  rules : Array[&DeriveRule],
  marker : String,
) -> &DeriveRule? {
  for r in rules {
    if marker_of(r) == marker {
      return Some(r)
    }
  }
  None
}

///|
/// 取全部规则键（按注册顺序）。
pub fn rule_keys(rules : Array[&DeriveRule]) -> Array[String] {
  let out : Array[String] = []
  for r in rules {
    out.push(key_of(r))
  }
  out
}

///|
/// 取全部标记 trait 名（按注册顺序）。
pub fn marker_names(rules : Array[&DeriveRule]) -> Array[String] {
  let out : Array[String] = []
  for r in rules {
    out.push(marker_of(r))
  }
  out
}

///|
/// 名字是否合法：只允许小写字母、数字与下划线（规则键用）。
pub fn is_valid_rule_name(name : String) -> Bool {
  if name.length() == 0 {
    return false
  }
  let mut ok = true
  let n = name.length()
  let mut i = 0
  while i < n {
    let c = name.at(i)
    let good = (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95
    if !good {
      ok = false
    }
    i = i + 1
  }
  ok
}

///|
/// 规则键为什么用不了；键**合法**时返回 `None`。
///
/// 区分「名字不合法」与「名字合法但没注册」是有意义的：前者的修法是改拼写
/// （`Field-Names` → `field_names`），后者要么换个已注册的规则，
/// 要么自己注册一条。笼统地回一句「未知规则」，用户会去翻注册表，
/// 而问题其实在拼写上。
pub fn invalid_rule_name_reason(name : String) -> String? {
  if is_valid_rule_name(name) {
    None
  } else {
    Some(
      "规则名 `" +
      name +
      "` 不合法：只允许小写字母、数字与下划线（例如 field_names）",
    )
  }
}
