// 内置规则集合。
//
// 新增内置规则的步骤：
//   1. 在 `moonforge/derive` 里加目标 trait 与对应的标记 trait（或复用已有的）；
//   2. 在本目录新建 `xxx.mbt`，定义一个规则类型并写
//      `pub impl @forge.DeriveRule for XxxRule with ...`；
//   3. 在下面 `all()` 的数组里加一项；
//   4. 补一组用例。
// 不需要修改词法 / 语法 / 代码生成等任何核心代码。
//
// 注意第三方规则**不必**塞进这个数组：`all()` 只是"随工具发行的一套默认规则"，
// 调用方可以把它与自家规则合并后再交给 `@forge.generate(...)`。
// 仓库里的 `examples/extension/` 就是这样一条完全独立于本文件的第三方规则。

///|
/// 全部内置规则。数组顺序即 `list-rules` 的展示顺序。
pub fn all() -> Array[&@forge.DeriveRule] {
  [
    FieldNamesRule::{ } as &@forge.DeriveRule,
    ValidateRule::{ } as &@forge.DeriveRule,
    DiffRule::{ } as &@forge.DeriveRule,
    ToPairsRule::{ } as &@forge.DeriveRule,
  ]
}
