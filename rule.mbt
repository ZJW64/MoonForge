// 规则接口与注册表。
//
// “可扩展性”的落点：`Rule` 是**公开的普通值**，规则集合是一个 `Array[Rule]`。
// 因此新增一条规则 = 新增一个文件 + 在集合里加一项；第三方也可以把本包作为依赖，
// 注入自己的规则集合。这不需要编译器提供任何扩展点。

///|
/// 一条派生规则。
pub(all) struct Rule {
  name : String
  description : String
  /// 生成函数。返回 `None` 表示“该规则不适用于这个类型”
  /// （例如只处理结构体的规则遇到枚举），而不是错误。
  gen : (TypeDef) -> String?
}

///|
pub fn Rule::apply(self : Rule, td : TypeDef) -> String? {
  (self.gen)(td)
}

///|
/// 按名字查找规则。
pub fn find_rule(rules : Array[Rule], name : String) -> Rule? {
  for r in rules {
    if r.name == name {
      return Some(r)
    }
  }
  None
}

///|
/// 取全部规则名（按注册顺序）。
pub fn rule_names(rules : Array[Rule]) -> Array[String] {
  let out : Array[String] = []
  for r in rules {
    out.push(r.name)
  }
  out
}

///|
/// 规则名是否合法：只允许小写字母、数字与下划线。
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
/// 规则名为什么用不了；名字**合法**时返回 `None`。
///
/// 区分"名字不合法"与"名字合法但没注册"是有意义的：前者的修法是改拼写
/// （`@derive(Field-Names)` → `field_names`），后者要么换个已注册的规则，
/// 要么自己注册一条。笼统地回一句"未知规则"，用户会去翻注册表，而问题
/// 其实在拼写上。
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
