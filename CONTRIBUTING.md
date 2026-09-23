# 贡献指南 · Contributing to MoonForge

感谢你愿意花时间。这份文档只写**这个仓库特有的约定**，通用的开源礼仪不重复。

## 1. 本地开发流程

```bash
git clone https://github.com/ZJW64/MoonForge && cd MoonForge

moon check                # 编译
moon test --target js      # 跑测试（96 个用例）
bash scripts/e2e.sh       # 一条命令复现 CI 的全部检查（推荐提交前必跑）
```

工具链版本：本仓库的格式化基线是 `moon 0.1.20260915`。如果你的 `moon fmt --check`
因为排版风格差异失败，先确认版本，再决定是升级基线还是改代码。

## 2. 提交前必须做的事

| 步骤 | 命令 | 为什么 |
|---|---|---|
| 格式化 | `moon fmt` | 仓库必须通过 `moon fmt --check`。生成物也要对齐 `moonfmt` 的形状，否则用户格式化一次就会让 `check` 永久报漂移 |
| 重新生成 | `moon run cmd/main -- gen examples` | 改了 `examples/` 或任何规则的输出格式，**必须同步提交生成物** |
| 无漂移 | `moon run cmd/main -- check examples` | 生成物与源文件必须一致。这条挂了 CI 一定会红 |
| 编译 | `moon check` | 生成代码的正确性由编译器裁决，不由工具的自我声明裁决 |
| 测试 | `moon test --target js` | 单元 + 金样 + 幂等 + 集成 |
| 端到端 | `bash scripts/e2e.sh` | 6 个阶段：漂移 / 测试 / 真编译 / 格式化稳定性 / CRLF 容忍 / 退出码契约 |

`examples/models_derive_gen.mbt` 是**提交进仓库的**。这不是失误，是设计：
让它参与 `moon check`，并且让 `check` 能检出"改了源码却忘记重新生成"。
**不要**把它写进 `.gitignore`。

## 3. 提交信息规范

采用 [Conventional Commits](https://www.conventionalcommits.org/)，**标题一行英文前缀 + 中文描述**，
**正文用中文，并且必须写清两件事**：

1. **为什么改**（原来的行为是什么、有什么问题——最好能复现）；
2. **怎么验证**（跑了什么命令、看到什么结果）。

推荐结构：

```
<type>(<scope>): <一句话说清改了什么>

<原来的行为 / 问题是什么。如果是 bug，写清复现路径；如果是新功能，写清动机。>

<改动要点，可以分条列。>

验证：
- <命令> → <结果>
```

`type` 取值：`feat` / `fix` / `ci` / `docs` / `chore` / `style` / `refactor` / `test`。
`scope` 常用：`parser` / `lexer` / `codegen` / `rules` / `cli` / `io` / `diagnostics` / `repo` / `tests` / `release`。

**反例**（这个仓库里不要出现）：

```
fix bug            ← 改了哪儿、为什么、怎么验，一个都没说
update code        ← 同上
WIP                ← 别提交 WIP，用本地 commit --amend 或 stash
```

**正例**（本仓库的真实提交）：

```
fix(parser): 位置参数结构体吞并后续声明，并切干净字段类型原文

`struct Point(Int, Int)` 后面紧跟另一个声明时，解析器会越过 `)` 继续找 `{`，
把下一个声明的字段体当成 Point 的字段：Point 报告出 4 个字段，下一个声明
则整个消失。生成物因此编译不过 —— 这是最严重的一类缺陷，因为它在
"生成成功"的表象下产出的是错代码。

验证：
- 新增 parser 单测：位置参数结构体后紧跟 Record，断言两者字段互不串味
- moon test --target js → 96 passed
- bash scripts/e2e.sh 第 1 阶段断言生成物里不含 `Point::`
```

## 4. 代码风格

- 一律 `moon fmt`，不做手工排版争论；
- **注释解释"为什么"，不复述"做了什么"**。`// i = i + 1` 这种注释不要写；
- 中文注释可以且欢迎——本仓库的注释都是中文；
- 关键取舍要留注释说明**被放弃的替代方案**。例如 `type_model.mbt` 里
  `BodyKind` 的解释写了"如果只看 `TypeKind`，生成器就会对位置参数结构体生成出一个空字段列表"，
  这样后来人不会把它简化回去。

## 5. 加一条规则

见 [`docs/扩展规则指南.md`](docs/扩展规则指南.md)。核心纪律一句话：

> 生成物要能过 `moon check`。**只对类型名白名单内的类型生成代码，不确定就跳过并留说明行。**
> "生成编译不过的代码"比"少生成代码"严重得多。

## 6. 改生成器输出格式 = 破坏性变更

任何让生成物字节发生变化的改动（换个空格、调个顺序、改成 `///|` 之外的形式），
都必须在**同一条提交**里重新生成 `examples/`，并在 `CHANGELOG.md` 里记一条。
否则所有用户的 `check` 会在升级后立刻报漂移——这是这类工具最容易被骂的地方。

## 7. Pull Request

用仓库的 [PR 模板](.github/PULL_REQUEST_TEMPLATE.md)。提交前自问三句：

1. `bash scripts/e2e.sh` 过了吗？
2. 如果是改输出，`examples/` 的生成物一起提交了吗？
3. 提交信息里写清"为什么"和"怎么验证"了吗？

## 8. Issue

- Bug：用 [Bug 报告模板](.github/ISSUE_TEMPLATE/bug_report.md)。**请附上能复现的最小 `.mbt` 片段**和 `moon version`——
  这类工具的问题高度依赖输入文本与工具链版本；
- 新规则 / 新功能：用 [功能建议模板](.github/ISSUE_TEMPLATE/feature_request.md)。请写清"生成什么函数、前置条件是什么、跳过什么"。

## 9. 许可证

提交即表示你同意以 [Apache-2.0](LICENSE) 授权你的贡献。
