# Muta

Mutation testing for Elixir, fast enough to run before every commit.

Muta changes your code in small, deliberate ways — flipping a `<` to a `<=`,
a `+` to a `-` — and re-runs the tests that cover the changed line. A mutant
that no test notices is a gap in your suite: the line is executed, but its
behaviour isn't pinned.

## Why it's fast

Every other Elixir mutation tester copies your project to a temp directory,
shells out to `mix test`, and parses stdout for a verdict. Muta stays inside
the running BEAM:

```
parse to AST → mutate → Code.compile_quoted → :code.load_binary
             → ExUnit.run/1 on covering tests → restore original binary
```

No temp directories, no subprocesses, no output scraping. A mutant costs
roughly 20ms instead of several seconds, and the verdict arrives as a
`%{failures: n}` struct rather than a regex match against a summary line
that changes between Elixir releases.

## Status

Early. Not published to Hex.
