// MoonForge 内部词法/语法/规则基础设施。
//
// 设计约束（见 docs/项目方案（完善版）.md 第 5.2 节）：
// 只解析“顶层类型定义”，函数体、表达式、宏等内容整体跳过。
// 这样做的代价是“不是完整的 MoonBit 解析器”，收益是对语言演进鲁棒、实现量可控。

///|
/// 词法单元种类：只覆盖“识别顶层类型定义”所需的最小集合。
pub(all) enum TokKind {
  Ident
  Doc
  Newline
  LParen
  RParen
  LBracket
  RBracket
  LBrace
  RBrace
  Comma
  Colon
  Question
  Bang
  Equals
  Bar
  Other
  Eof
} derive(Debug, Eq)

///|
/// 一个词法单元。
///
/// `text` 对 `Doc` 是注释正文（已剥离 `///` 前缀与 `///|` 分隔符）；
/// 对 `Ident` 是标识符本身；其他种类保留原文切片。
///
/// `start` / `end` 是相对于源文件字符串的 UTF-16 偏移，左闭右开。
/// 解析“字段类型原文”时可以直接用这两个偏移切片，避免拼接 token 丢失空白与符号。
pub(all) struct Token {
  kind : TokKind
  text : String
  start : Int
  end : Int
  line : Int
} derive(Debug, Eq)

///|
/// 在给定下标处取 token；越界返回一个 `Eof` 哨兵，避免调用方到处写边界判断。
pub fn tok_at(toks : Array[Token], i : Int) -> Token {
  if i >= 0 && i < toks.length() {
    toks[i]
  } else {
    { kind: Eof, text: "", start: 0, end: 0, line: 0 }
  }
}
