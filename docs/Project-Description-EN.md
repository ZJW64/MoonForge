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

Three design decisions carry the project:

1. **Zero syntax intrusion.** Derive requests live in plain **doc comments**
   (`/// @derive(validate, diff)`). No new attribute, no grammar change — the IDE and
   `moon fmt` both stay happy.
2. **Generated into the same directory as the source.** A MoonBit package boundary *is* a
   directory, and private fields are only visible within the same package. Generating in place
   allows direct field access **without forcing users to make fields `pub`**.
3. **Generated files are committed, and CI checks for drift.** Output is byte-stable, and
   `moonforge check` returns non-zero when a source file changed but its generated file did not.
   This turns generated code from a one-off script into a maintainable engineering asset.

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
| Rule interface & registry | `Rule` is a public plain value; adding a rule = one new file + one registry entry |
| **4 built-in rules** | `field_names`, `validate` (annotation-driven), `diff`, `to_pairs` |
| CLI | `list-rules` / `explain` / `gen` / `check`; exit-code contract `0` / `1` / `2` |
| Tests | **10 layers, 96 cases, green on both `js` and `wasm-gc`** |
| One-command acceptance | `bash scripts/e2e.sh` — 6 stages: drift / tests / real compile / format stability / CRLF tolerance / exit-code contract |
| Examples | `examples/` ships inputs, the **committed generated file**, and tests that call generated methods directly |
| CI | GitHub Actions, ubuntu **and** windows, format check + drift check + both backends |

Explicitly **not** in scope: compiler plugins, runtime reflection, comptime. The project does not
claim to extend `derive()` — `derive()`'s own behavior is untouched.

## Evidence

| Claim | How to verify |
|---|---|
| Generated code actually works | `examples/models_wbtest.mbt` calls `User::validate` / `User::diff` / `User::field_names` / `User::to_pairs`. **No handwritten implementation of these methods exists in the repository** |
| Generated code actually compiles | The generated file is committed, so `moon check` really compiles it. Delete it and `moon check` fails |
| Drift is caught | `moon run cmd/main -- check <dir>` returns exit code `1` after a source edit; locked in by e2e stage 6 |
| Formatting cannot break the loop | The generator's bytes match `moon fmt`'s output (e2e stage 4) — otherwise one `moon fmt` run would make `check` report permanent drift |
| No false positives on Windows | A CRLF-converted generated file still passes `check` (e2e stage 5); `.gitattributes` pins `*.mbt` to LF |
| Rules are genuinely pluggable | `to_pairs` was added as the 4th rule using exactly the documented flow — `lexer.mbt` / `parser.mbt` / `codegen.mbt` were not touched |

```bash
$ moon test --target js
Total tests: 96, passed: 96, failed: 0.

$ bash scripts/e2e.sh
== 1/6 drift check: committed generated files match sources
== 2/6 run tests
== 3/6 compile check (including generated code)
== 4/6 formatting: repo is formatted, generated output is format-stable
== 5/6 CRLF tolerance: check still passes after converting output to CRLF
== 6/6 drift loop and exit-code contract
OK: all end-to-end checks passed.
```

## Reproduce in 5 minutes

```bash
git clone https://github.com/ZJW64/MoonForge && cd MoonForge
moon check                                             # compiles generated code too
moon run cmd/main -- explain examples/models.mbt       # see the tool explain itself
moon test --target js                                  # 96 cases
bash scripts/e2e.sh                                    # 6 end-to-end stages
```

## Roadmap and blockers

| Version | Content | Status / blocker |
|---|---|---|
| v0.2.0 | `to_pairs` rule, newline normalization, stale-output cleanup, format self-consistency, stricter exit-code contract, multi-OS CI | ✅ **shipped** |
| v0.3 | More rules (Builder / Visitor / `to_json`), `--target` variants, incremental generation | No blocker |
| v1.0 | **Semantic (AST-level) code generation** | ⛔ Requires the compiler to expose AST access — does not exist today |
| v2.0 | **Compile-time execution (comptime)** | ⛔ Requires compiler support for evaluating user functions at compile time — does not exist today |

Blockers are stated explicitly rather than glossed over — that is part of understanding the
engineering boundary.
