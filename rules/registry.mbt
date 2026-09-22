// 内置规则集合。
//
// 新增规则的完整步骤：
//   1. 在本目录新建 `xxx.mbt`，写一个返回 `@forge.Rule` 的公开函数；
//   2. 在下面 `all()` 的数组里加一项；
//   3. 在 tests 目录补一组用例。
// 不需要修改词法/语法/代码生成等任何核心代码。

///|
/// 全部内置规则。数组顺序即 `moonforge list-rules` 的展示顺序。
pub fn all() -> Array[@forge.Rule] {
  [field_names(), validate(), diff()]
}
