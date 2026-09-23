# 更新日志

本文件记录 MoonForge 的每一处**行为变化**。格式参考
[Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

> 本项目处于 0.x，任何版本都可能调整公开 API；每次调整都会出现在下面的
> "变更"一节里。生成物里带有版本号，因此**升级版本必然触发一次漂移**
> （`moonforge check` 返回 1），跑一次 `moonforge gen` 即可 —— 这是设计
> 如此，不是故障。

## [未发布]

## [0.2.0] - 2026-09-23

本轮的主题是**让工具与它自己的判据自洽**：修掉的每一条 bug 都是同一个形状 ——
工具的输出/判断在某个边界上和自己矛盾，用户照着提示做也修不好。

### 新增

- 第 4 条内置规则 **`to_pairs`**：为 struct 生成
  `T::to_pairs(self) -> Array[(String, String)]`，只收 `String` 字段，
  其余字段跳过并在生成文件里留说明行（与 `validate` 同一套白名单纪律）。
  → 场景：表单渲染、日志、只认字符串的接口。
- `moonforge gen` 会**清理残留生成物**：源文件里的 `@derive` 删光之后，
  上一次生成的 `*_derive_gen.mbt` 会被删除并打印 `removed ... [源文件里已没有
  @derive 标记]`。此前 `check` 会一直报"多余的生成文件"，而照提示跑 `gen`
  也修不好。
- 诊断信息按**原因**分类，不再笼统地说"不支持"：
  - 规则名不合法 → `规则名 \`Field-Names\` 不合法：只允许小写字母、数字与下划线`
  - 规则名合法但未注册 → `未知规则 \`no_such_rule\`；可用 moonforge list-rules 查看`
  - 规则不适用 → 分别给出 `该规则只支持 struct 定义` /
    `X 是位置参数（元组）结构体，没有具名字段` /
    `X 的声明里没有找到字段体（既没有 ( 也没有 {）`
- `explain` 会显示 `struct(位置参数)` / `struct(无字段体)`，这类声明后面不会
  跟任何 `field` 行，不解释会显得像解析失败。
- **换行符容忍**：解析与漂移比较前统一把 CRLF/CR 归一成 LF，生成侧恒定产出 LF。
- `scripts/e2e.sh` 从 4 阶段扩到 6 阶段：新增"先 `moon fmt` 再 `check`"、
  "生成物换成 CRLF 后 `check` 仍须通过"、"退出码契约（0/1/2）"、"`gen` 清理
  残留"四类断言；漂移负例改为在 `_build` 下的副本上进行，不再改动仓库文件。

### 修复

- **位置参数结构体会吞并后续声明**（最严重）：
  `struct Point(Int, Int)` 之后的第一个 `{`（属于**下一个**声明）被当成了它的
  字段体，于是 `Point::field_names()` 返回下一个结构体的字段名、`Point::diff`
  引用不存在的字段 —— 生成**编译不过**的代码，而中间那个声明被静默丢弃。
- **字段类型的尾随逗号进入类型原文**：`a : String,` 的类型是 `"String,"`，
  白名单匹配失败，`@nonempty` 被静默跳过。现在深度 0 的逗号终止类型切片，
  括号里的逗号（元组类型、泛型实参）保留。
- **跨行书写的字段类型把换行带进 IR**：`Map[\n String,\n Int\n]` 现在折叠为
  `Map[ String, Int ]`，跨行与单行得到同一个类型字符串。
- **带载荷的枚举把参数类型名当成变体**：`enum Payload { A(Int) B(String, Int) }`
  原本输出 `["A","Int","B","String","Int"]`，现在只收集构造器名。
- **单行结构体的字段继承类型上的注解**：`struct A { x : Int }` 上面的注释会被
  复制到字段 `x` 头上，可能生成用户根本没请求的校验代码。
- **生成物与 `moon fmt` 不一致**：用户跑一次 `moon fmt` 之后 `check` 会永远报
  "内容过期"，而再跑 `gen` 也修不好。原因是"跳过说明行"与紧随其后的 `///|`
  之间缺少 `moon fmt` 要求的空行。
- **`check` 遇到不存在的路径退出码为 0**：把 `check src` 写成 `check scr`，
  CI 一片绿，其实一个文件都没检查。现在路径不存在 / 非 `.mbt` / 目录里没有
  `.mbt` 一律退出码 2。
- 从仓库中删除误提交的 `.Rhistory`（根目录与 `.github/workflows/` 各一个），
  并在 `.gitignore` 中挡住它。

### 变更

- 三条内置规则的前置判断由 `is_enum()` 统一换成 `TypeDef::has_named_fields()`：
  `struct Point(Int, Int)` 在类型种类上仍是 struct，但"按字段名展开"的规则对它
  没有意义。判断条件收敛到一处，将来新增字段体形态不会漏掉某条规则。
- 新增公开 API：`BodyKind`（`Record` / `Positional` / `Variants` / `Missing`）、
  `TypeDef::has_named_fields()`、`TypeDef::body_label()`、
  `with_notes()`、`normalize_newlines()`、`not_applicable_reason()`、
  `invalid_rule_name_reason()`。`TypeDef` 增加 `body` 字段。
- 全仓库按 `moon fmt` 规范化；`moon.pkg` 里的冗余 `@alias` 被格式化器移除
  （别名默认取包路径最后一段，`@forge` 这类真正需要的别名被保留）。
- `moon.mod` 补上 `repository` 字段。
- 版本号 0.1.0 → 0.2.0。

### 兼容性

- `TypeDef` 是公开类型且新增了字段 `body`，直接构造 `TypeDef` 字面量的代码需要
  补上该字段（本仓库内只有测试这么做）。以库依赖方式使用、只读 `TypeDef` 的
  代码不受影响。

### 测试

- 用例数 62 → 96（解析 10 条、规则 9 条、诊断 6 条、`with_notes` 3 条、
  换行符 3 条、端到端 2 条）。
- 端到端：`bash scripts/e2e.sh` 6 个阶段全部通过。

## [0.1.0] - 2026-09-22

首个版本。

### 新增

- 词法分析（`lexer.mbt`）：只切 token，字符串 / 注释 / 原始字符串行整体跳过。
- 子集语法分析（`parser.mbt`）：只在花括号深度 0 认 `struct` / `enum`。
- 类型模型 IR（`type_model.mbt`）、规则接口与注册表（`rule.mbt`）。
- 代码生成（`codegen.mbt`）：输出字节稳定，生成文件头带来源与重现命令。
- 3 条内置规则：`field_names`、`validate`（注解驱动：`@nonempty` /
  `@min` / `@max` / `@positive`）、`diff`。
- CLI：`list-rules` / `explain` / `gen` / `check`，退出码约定
  `0 成功 · 1 检出漂移 · 2 参数或路径有误`。
- 8 层测试（L1 词法 ~ L8 CLI 地基），62 个用例；`examples/` 含输入、
  已提交的生成物，以及直接调用生成代码的端到端测试。
- GitHub Actions CI、`scripts/e2e.sh`、`docs/` 三份说明。

[未发布]: https://github.com/ZJW64/MoonForge/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/ZJW64/MoonForge/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/ZJW64/MoonForge/releases/tag/v0.1.0
