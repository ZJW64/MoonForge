# 更新日志

本文件记录 MoonForge 的每一处**行为变化**。格式参考
[Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

> 本项目处于 0.x，任何版本都可能调整公开 API；每次调整都会出现在下面的
> "变更"一节里。生成物里带有版本号，因此**升级版本必然触发一次漂移**
> （`moonforge check` 返回 1），跑一次 `moonforge gen` 即可 —— 这是设计
> 如此，不是故障。

## [0.3.0] - 2026-09-23

本轮的主题是**把派生入口从"工具私有的 doc comment"改成语言级的 trait impl**，
并让规则集合真正成为可替换、可扩展的基础设施。三处动机：

1. `/// @derive(...)` 是一条**只有 MoonForge 认识**的私有约定 —— 不参与类型检查、
   拼错不报错、换个工具就失效。派生入口应该是**语言层面的事实**。
2. 规则只有四条、且扩展要靠"改注册表数组"，生态价值弱。规则本身应该是
   **一个 SPI trait**，规则集合应该是**异构的 trait 对象数组**。
3. 派生的目标（`field_names` / `validate` / …）应该是**用户可实现的普通 trait**，
   而不是工具内部的一个字符串名字。

> **破坏性变更（必读）**：`/// @derive(...)` 写法**不再产出任何代码**。
> 老写法仍会被识别，并给出一条**可粘贴的**迁移提示。生成物形状也变了
> （见下），因此升级后必须跑一次 `moonforge gen`。

### 变更（破坏性）

- **派生入口改为真实的 trait impl。** 现在在类型所在文件里写一行：

  ```moonbit
  pub impl @derive.DeriveValidate for User with fn requested(_self) {}
  ```

  生成物变成 `pub impl @derive.Validate for User with fn validate(self) { ... }`。

  为什么是 `impl` 而不是 `derive(...)`：编译器的 `derive(...)` **只认内置 trait 白名单**，
  对自定义 trait 直接报 `Don't know how to derive trait X`（E4077），所以它**不能**作为
  扩展入口；而普通 `impl` 没有这个限制，且能被 `moon check` 真正编译 ——
  于是"拼错标记名"这类错误在编译期就暴露，不必等工具来猜。

  `_self` 那个空方法不是装饰：MoonBit 语法**不允许** `impl T for X {}` 这样的空块
  （报 `Invalid grouped impl declarations`），标记 trait 必须带至少一个方法。

- **生成的 impl 头不再写返回类型。** 由 trait 声明唯一决定，实现只提供方法体。
  这不是风格偏好，是为了与 `moon fmt` 逐字节一致的硬约束（见"修复"第一条）。

### 新增

- **`moonforge/derive` 包**：4 个派生目标 trait（`FieldNames` / `Validate` / `Diff` /
  `ToPairs`）与 4 个标记 trait（`DeriveFieldNames` / `DeriveValidate` / `DeriveDiff` /
  `DeriveToPairs`）。目标 trait 是**用户可以自己实现、也可以自己定义同类 trait** 的
  普通 trait；标记 trait 是"这个类型请求了这次派生"的语言级声明。
- **规则 SPI 改为 trait**：`pub(open) trait DeriveRule { fn head(Self) -> RuleHead;
  fn generate(Self, TypeDef) -> Fragment? }`，注册表是
  `Array[&@forge.DeriveRule]` —— 异构规则对象放进同一个数组里统一遍历。
  第三方可以**只依赖 `moonforge` 包、不改它的源码**，把自己的规则并进集合。
- **`examples/extension/`：可运行的第三方扩展样例。** 它自带 `ToCsv` / `DeriveToCsv`
  trait、一个 `ToCsvRule`，把内置规则与自己的规则合成新集合后直接生成，全程没碰
  moonforge 源码；`tocsv_wbtest.mbt` 用 5 条测试把它钉住（含"只用自己的规则集时，
  内置规则完全不出场"）。
- **三条新的可操作诊断**：
  - 标记名不存在 → 列出已注册标记，并在"把**规则键**误写成标记名"时直接点破；
  - 老写法 `/// @derive(...)` → 给出**可粘贴**的新 `impl` 代码；
  - impl 头超列宽预算 → 说明会被 `moon fmt` 折开、给出三条出路。
- **锚定解析能力**：识别 `impl <前缀>.<标记> for <类型>`，支持包前缀 / 多级包路径 /
  无前缀同包 trait / 泛型目标（`for Box[T]` → `Box`），并**排除固有 impl**
  （`impl Foo with ...`）；impl 体内的花括号与同名关键字不会污染后续扫描。
- **`scripts/fmt_budget_probe.sh`**：用真实 `moonfmt` 现场实测生成物的列宽预算
  （构造预算两侧的 impl 头，断言预算内保持、超预算折开），并接进 `e2e.sh` 第 4 阶段。
  预算值不是猜的，量不到预期就非零退出。
- **`MOONFORGE_VERSION` 与生成物的一致性**：生成物头的 `entry` 行写明**当前**入口写法，
  打开生成文件的人不必回翻文档。

### 修复

- **生成物与 `moon fmt` 不一致（本轮新发现）。** 生成的 impl 头形如
  `pub impl @derive.Validate for User with fn validate(self) -> Result[Unit, String] {`，
  **83～85 列**；而 `moonfmt` 对 82 列及以下的行保持原样、**83 列起**会把返回类型或
  参数表折开。于是生成物与格式化结果不一致 → 用户跑一次 `moon fmt`，`check` 就永久
  报漂移，而且 `gen` 也治不好（它照旧写单行版）。
  → 生成 impl 时**不写返回类型**（由 trait 声明决定），impl 头降到 58～61 列，
  留出约 20 列余量；同时新增列宽守卫，真的超预算时在生成阶段给出可操作的诊断。
  实测边界由 `scripts/fmt_budget_probe.sh` 钉住。仓库里的
  `examples/models_derive_gen.mbt` 现在与 `moonfmt` 的输出**逐字节相同**。
- **CI 在装完工具链后没有刷新包索引，导致 ubuntu 与 windows 两个平台同时变红。**
  官方安装脚本只下载工具链与 core，**不会**创建或更新 `~/.moon/registry`；而
  `cmd/main` 依赖 `moonbitlang/x`（用它的 `fs`），索引缺失时 `moon check` 在
  "计算构建计划"阶段就直接退出 —— **实测 0.09 秒、退出码非零，而且不产生任何
  编译错误信息**，极易被误判成代码问题：

  ```
  Warning: you may need to run `moon update` to update the registry
  Error: Failed to calculate build plan
  Caused by: Failed to resolve registry dependency `moonbitlang/x`
             for module `moonforge`: module was not found in the registry
  ```

  现象上有一个很好的判别特征：`moon version` 与 `moon fmt --check` 都通过
  （这两个命令不需要解析依赖），**只有 `moon check` 会秒失败**。
  → 在安装步骤后新增一步 `moon update`。
  复现方式：把 `~/.moon/registry` 移走再跑 `moon check`，即可看到同样的报错。
- 安装工具链的步骤补上 `set -euo pipefail`。`curl ... | bash` 的退出码取的是
  `bash` 的，下载被截断时 bash 读到 EOF 会返回 0 —— 步骤显示成功，工具链却是
  残缺的，报错会出现在毫不相关的地方。

### 兼容性（升级指南）

- **老写法不再产出代码。** `/// @derive(validate, diff)` 会被识别并给出一条迁移提示，
  内含可直接粘贴的新 `impl`。不做静默忽略，是因为"生成物莫名消失"比报错更难查。
- **生成物形状变化 + 版本号变化 → 必然触发一次漂移。** 升级后跑一次
  `moon run cmd/main -- gen <dir>` 即可，`check` 随之回到 0。这是设计如此。
- **公开 API 变化**（以库依赖方式使用时需注意）：
  - 移除 `Rule` 结构体（`name` / `description` / `gen`）→ 改为 `pub(open) trait DeriveRule`，
    配套 `RuleHead`（`key` / `marker` / `trait_name` / `description`）与 `Fragment`
    （`notes` / `impl_body`）；
  - `TypeDef::derive_rules` → `legacy_derive_rules`（只用于老写法迁移诊断）；
  - 新增 `ImplDecl` / `ParseResult` / `parse()` / `impl_head_line()` /
    `first_line()` / `FMT_WIDTH_BUDGET` 等公开 API；
  - `parse_source()` 保留，仍是"只要类型定义"的便捷入口。
- `moon.pkg` 需要新增一行对派生 trait 所在包的引用
  （`import { "moonforge/derive" @derive, }`），别名随意 —— 生成的 impl 会**复用你写
  标记时的前缀**，不会假设你把它叫 `@derive`。

### 测试

- 用例数 96 → 119。新增覆盖：入口解析 10 条、规则 SPI 与 trait 对象遍历 3 条、
  诊断 3 条（含列宽预算）、第三方扩展 5 条、生成物金样随形状更新。
- `bash scripts/e2e.sh` 6 个阶段全部通过；两个后端
  （`moon test --target js` / `--target wasm-gc`）119/119。

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

[0.3.0]: https://github.com/ZJW64/MoonForge/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/ZJW64/MoonForge/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/ZJW64/MoonForge/releases/tag/v0.1.0
