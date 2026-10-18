# MoonForge — English Project Description

**Project** MoonForge — a source-to-source derive code generator for MoonBit
**Category** Language & Developer Tooling
**Repository** <https://github.com/ZJW64/MoonForge>
**License** Apache-2.0 (original work, not a port, no third-party code copied)

## The problem

MoonBit's `derive(...)` only covers a **fixed whitelist of built-in traits**. The official
documentation ([error code E4077](https://docs.moonbitlang.com/en/latest/language/error_codes/E4077.html))
states it plainly:

> "MoonBit lets you derive implementations for some predefined traits. This means **you cannot
> make MoonBit automatically derive your own custom traits**."

The derive registry lives inside the compiler (`src/ast_derive.ml` holds a hard-coded
`Trait → Deriver` hash table) and there is no public registration point. The compiler also
exposes no AST, no proc-macros, and no comptime.

So whenever you need to generate **semantic** code for your own types — validation, field-name
enumeration, structural diffing, builders, visitors — you are left with two bad options:
hand-write the boilerplate per type (repetitive, easy to miss, drifts as fields change), or use
an external generic code generator (breaks the package boundary, cannot see private fields,
disconnected from `moon build`).

## The approach

MoonForge fills that gap **in user space**, with **100% MoonBit**:

```
.mbt source → lexer → subset parser → type-model IR → rule dispatch
           → codegen → sibling *_derive_gen.mbt → compiled together with handwritten code
```

The project is **general trait-derive infrastructure**, not "four rules and a script". A derive
request is made of three parts, and every part is a real language-level thing:

| Part | What it is | Example |
|---|---|---|
| **Target trait** | "what the type can do" — a plain MoonBit trait | `trait Validate { fn validate(Self) -> Result[Unit, String] }` |
| **Marker trait** | "this type requests that derive" | `trait DeriveValidate { fn requested(Self) -> Unit }` |
| **Rule** | "how to generate the implementation" — implements the SPI trait `DeriveRule` | `ValidateRule` |

Three design decisions carry the project:

1. **The entry point is a real trait impl, not a doc comment.**
   The user writes one line in the type's own file:
   `pub impl @derive.DeriveValidate for User with fn requested(_self) {}`.
   It is a **language-level** statement that the type requests this derive, so **`moon check`
   really compiles it** — a typo in the marker name is caught at compile time, and any tool can
   read it. (The entry deliberately does **not** use `derive(...)`: that only accepts the
   compiler's built-in trait whitelist and rejects custom traits with
   `Don't know how to derive trait X`, so it cannot serve as an extension point.)
2. **Generated into the same directory as the source.** A MoonBit package boundary *is* a
   directory, and private fields are only visible within the same package. Generating in place
   allows direct field access **without forcing users to make fields `pub`**.
3. **Generated files are committed, and CI checks for drift.** Output is byte-stable, and
   `moonforge check` returns non-zero when a source file changed but its generated file did not.
   This turns generated code from a one-off script into a maintainable engineering asset.

## The independent contribution (vs. existing reusable pieces)

Parsers already exist (`moonc`, [tree-sitter-moonbit](https://github.com/moonbitlang/tree-sitter-moonbit)); macros and
template expansion already exist ([MoonMacro](https://mooncakes.io/docs/faaaaa3/moonmacro)); string-concatenation
codegen is trivial. **None of that counts as this project's contribution**, and the ~780 lines of
lexer/parser in this repo are explicitly a *front-end adapter*.

The contribution is the layer in between — **defining "derive" as three contracts that three
different judges can check**:

| Contract | Content | Checked by |
|---|---|---|
| Entry | A derive request is a real trait impl | `moon check` (a typo in the marker name fails to compile) |
| Input | Rules only see `DeriveInput` (type name / body kind / normalised fields / the request that triggered it) | 6 contract tests |
| Output | Rules only return `Fragment` (notes + members, no return type) | `moon check` + byte-identical `moon fmt` + drift-free `check` |

Three structural facts back this up — none of them are adjectives:

1. **The front end is replaceable.** A test in `rules/rules_wbtest.mbt` builds a `DeriveInput`
   literal **without going through the parser at all** and still generates code; swapping the whole
   front end would not change a single rule.
2. **Rules are replaceable.** `examples/extension/` adds a third-party rule without touching the kernel.
3. **Output is a fixed point of the formatter.** `scripts/fmt_budget_probe.sh` measures the 82-column
   boundary against the real `moonfmt`; the generated file is byte-identical to its output.

Ablation: delete the parser and the contracts plus the rules still work; **delete the contract layer
and the project really does degrade to "a few templates plus artifact management"**.

The full argument, including a point-by-point comparison with MoonMacro, is in
[`核心贡献边界.md`](核心贡献边界.md) (Chinese).

## Boundary of the design

Committed generated code participates in `moon check`, so **"generating code that does not
compile" is far worse than "generating less code."** The project's discipline is therefore:

> Generate code only for types on an explicit **name whitelist**; when in doubt, skip the field
> and leave a `// moonforge:` explanation line. *Why* something was not generated is part of the
> product, exactly like what was generated.

Concretely, `validate` and `to_pairs` only act on `String` and eight built-in numeric types, and
every skipped field or inapplicable rule is explained in the output.

## What was delivered

| Item | Detail |
|---|---|
| Lexer + subset parser + type-model IR | Only `struct` / `enum` at brace depth 0; `BodyKind` separates record / positional / missing body |
| Derive infrastructure | `moonforge/derive`: 4 target traits + 4 marker traits; `DeriveRule` SPI; **`DeriveInput` as the single input contract** (front end and rules meet here); heterogeneous `Array[&DeriveRule]` registry; three actionable diagnostics |
| Rule interface & registry | Rules implement `pub(open) trait DeriveRule`; adding a rule = implement the trait + add it to the set. A third party can extend the tool **without modifying its source** |
| **4 built-in rules** | `field_names`, `validate` (annotation-driven), `diff`, `to_pairs` |
| CLI | `list-rules` / `explain` / `gen` / `check`; exit-code contract `0` / `1` / `2` |
| Third-party extension sample | `examples/extension/`: ships its own target trait, marker trait and rule; a runnable proof that no core source was touched |
| Tests | **11 layers, 126 cases, green on both `js` and `wasm-gc`** |
| One-command acceptance | `bash scripts/e2e.sh` — 6 stages: drift / tests / real compile / format stability (incl. measured line-width budget) / CRLF tolerance / exit-code contract |
| Examples | `examples/` ships inputs, the **committed generated file**, and tests that call generated methods directly |
| CI | GitHub Actions, ubuntu **and** windows, format check + drift check + both backends |

Explicitly **not** in scope: compiler plugins, runtime reflection, comptime. The project does not
claim to extend `derive()` — `derive()`'s own behavior is untouched, and deliberately does not use
it as the entry point (see above).

**Migration note.** The old entry-point form, a doc comment `/// @derive(validate, diff)`, is still
recognised but no longer emits code: it produces a copy-pasteable migration message instead. The
generated output shape also changed, so upgrading requires one `moonforge gen` run — the version
string in the file header would have triggered a drift anyway.

## Evidence

| Claim | How to verify |
|---|---|
| Generated code actually works | `examples/models_wbtest.mbt` calls the generated `Validate::validate` / `Diff::diff` / `FieldNames::field_names` / `ToPairs::to_pairs`. **No handwritten implementation of these methods exists in the repository** |
| Generated code actually compiles | The generated file is committed, so `moon check` really compiles it. Delete it and `moon check` fails |
| Drift is caught | `moon run cmd/main -- check <dir>` returns exit code `1` after a source edit; locked in by e2e stage 6 |
| Formatting cannot break the loop | The generator's bytes are **byte-identical** to `moon fmt`'s output (e2e stage 4); the line-width boundary is measured against the real `moonfmt` by `scripts/fmt_budget_probe.sh` — otherwise one `moon fmt` run would make `check` report permanent drift |
| No false positives on Windows | A CRLF-converted generated file still passes `check` (e2e stage 5); `.gitattributes` pins `*.mbt` to LF |
| Rules are genuinely pluggable | `examples/extension/tocsv_wbtest.mbt` (5 cases) proves a third-party rule registers and takes effect **without changing a single line of MoonForge source**, that the package prefix is reused, that a custom-only rule set excludes the built-ins, and that unregistered markers are reported |
| Format budget is measured, not guessed | `bash scripts/fmt_budget_probe.sh` → `OK: line-width budget 82 holds (4 of 4 wrapped)` |

```bash
$ moon test --target js
Total tests: 126, passed: 126, failed: 0.

$ bash scripts/e2e.sh
== 1/6 drift check: committed generated files match sources
== 2/6 run tests
== 3/6 compile check (including generated code)
== 4/6 formatting: repo is formatted, generated output is format-stable
OK: line-width budget 82 holds (4 of 4 wrapped)
== 5/6 CRLF tolerance: check still passes after converting output to CRLF
== 6/6 drift loop and exit-code contract
OK: all end-to-end checks passed.
```

## Reproduce in 5 minutes

```bash
git clone https://github.com/ZJW64/MoonForge && cd MoonForge
moon check                                             # compiles generated code too
moon run cmd/main -- explain examples/models.mbt       # see the tool explain itself
moon test --target js                                  # 126 cases
bash scripts/e2e.sh                                    # 6 end-to-end stages
```

## Roadmap and blockers

| Version | Content | Status / blocker |
|---|---|---|
| v0.2.0 | `to_pairs` rule, newline normalization, stale-output cleanup, stricter exit-code contract, multi-OS CI | ✅ shipped |
| v0.3.0 | **Derive-infrastructure rework**: entry point moved to a language-level trait impl; `DeriveRule` SPI + heterogeneous rule-object array; third-party extension sample; line-width budget guard | ✅ **shipped** |
| v0.4 | More rules (Builder / Visitor / `to_json`), `--target` variants, incremental generation | No blocker |
| v1.0 | **Semantic (AST-level) code generation** | ⛔ Requires the compiler to expose AST access — does not exist today |
| v2.0 | **Compile-time execution (comptime)** | ⛔ Requires compiler support for evaluating user functions at compile time — does not exist today |

Blockers are stated explicitly rather than glossed over — that is part of understanding the
engineering boundary.
