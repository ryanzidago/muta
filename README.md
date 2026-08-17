<p align="center">
	<img src=".assets/logo.svg" alt="" width="96">
</p>

<h1 align="center">muta</h1>

<p align="center">
	Mutation testing for Elixir. You name the code and the tests; it tells you what your tests miss.
</p>

<p align="center">
	<img src="https://img.shields.io/badge/elixir-~%3E%201.20-4B275F" alt="Elixir ~> 1.20">
	<img src="https://img.shields.io/badge/status-alpha-F2A63C" alt="Status: alpha">
	<img src="https://img.shields.io/badge/license-MIT-6E4A7E" alt="License: MIT">
</p>

---

Your tests cover the line. That does not mean they pin what it does.

muta changes your code in small ways, re-runs the tests you gave it, and reports
every change no test noticed:

```
  lib/store/pricing.ex:5
    - cents > 5000
    + cents >= 5000
    survived
```

Free shipping over $50 can become free shipping at exactly $50 and those tests
stay green. Nobody tested a cart at 5000 cents.

## Install

1. Add the dependency:

	```elixir
	{:muta, github: "fabioelizandro/muta", only: [:dev, :test]}
	```

2. muta runs your tests in process, so the task needs the test environment:

	```elixir
	def cli do
	  [preferred_envs: [mutate: :test]]
	end
	```

## Usage

Give it the source files to mutate and the test files to judge them by.

```shell
mix mutate lib/store/pricing.ex --test test/store/pricing_test.exs
```

Both are repeatable:

```shell
mix mutate lib/store/pricing.ex lib/store/cart.ex \
  --test test/store/pricing_test.exs --test test/store/cart_test.exs
```

```
$ mix mutate lib/store/pricing.ex --test test/store/pricing_test.exs
Mutating lib/store/pricing.ex
Judged by test/store/pricing_test.exs

  lib/store/pricing.ex:5
    - cents > 5000
    + cents >= 5000
    survived

8 mutants · 7 killed · 1 survived · 0 invalid · 87.5%
```

| Outcome      | Means                                                                |
|--------------|------------------------------------------------------------------------|
| **killed**   | A test failed. That behaviour is pinned.                               |
| **survived** | Every test passed. Nothing pins it. This is the output you act on.     |
| **invalid**  | The compiler rejected the change. Left out of the score.               |

Exit code is `1` when anything survived, `0` when nothing did.

## muta does not find your tests

This is the one thing to understand before trusting the output.

muta judges each mutant **only by the tests you name**. A survivor means *those
tests did not catch it* — not that nothing in your suite would. Name too few
tests and you will get survivors that some other test already kills.

That is a deliberate scope. Working out which tests exercise a given function is
a genuinely hard problem, and every cheap answer is wrong in a way you cannot
see: filenames assume a layout, and static call graphs break at protocols,
behaviours and LiveView callbacks. Runtime coverage answers it properly, and
costs a full serialised suite run to build.

So muta does not guess. It does one job, and the selection problem stays outside
where you can see it and solve it however suits you — by hand, from a coverage
report, or from a tool built for it.

## Speed

There is no cache, no coverage map, and nothing written to disk. Every run
computes from the source in front of it.

On a Phoenix application with roughly 1,900 tests, mutating a domain module
against its test file takes about **2.2 seconds**, start to finish. Cost scales
with the tests you name, not with the size of your suite.

## Why it is fast

The usual design copies your project to a temp directory, applies the mutation
on disk, shells out to `mix test`, and reads stdout. That is a compile and a VM
boot for every mutant.

muta stays in the BEAM you are already running:

```
source → AST → mutate one node → Code.compile_quoted → :code.load_binary
       → ExUnit.run/1 on your tests → restore the original binary
```

A mutant is loaded rather than written, which costs milliseconds, and `ExUnit`
stops at the first failure, so a mutant that dies does so immediately.

## Mutations

One mutator ships today,
[`Muta.Mutator.Comparison`](lib/muta/mutator/comparison.ex). Comparisons came
first because that is where off-by-one lives and where weak tests hide.

| Change    | Turns                                       |
|-----------|-----------------------------------------------|
| Boundary  | `a < b` → `a <= b`, `a >= b` → `a > b`      |
| Inverse   | `a < b` → `a > b`, `a >= b` → `a <= b`      |
| Equality  | `a == b` → `a != b`, `a === b` → `a !== b`  |

## What muta refuses to do

A mutation score you cannot trust is worse than none, because it reads as
reassurance. muta raises `Muta.UntrustworthyError` and stops when it finds:

| It finds                                                    | Because                                                                       |
|---------------------------------------------------------------|---------------------------------------------------------------------------------|
| A test failing on your unmutated code                         | Every mutant would look killed and the score would look perfect.               |
| Two runs of your tests disagreeing                            | A suite that leaks state kills mutants for reasons unrelated to the mutation.  |
| A process still running a mutant after its test finished      | The next mutant would be judged partly against this one.                       |
| Your tests not finishing in `:baseline_timeout_ms`            | There is no honest deadline to hold a mutant to.                               |

## Programmatic use

The mix task is a shell over the library. Run it inside your test environment
with ExUnit autorun off and your test files loaded, which is what the task sets
up for you.

```elixir
config = Muta.Config.new(["lib/store/pricing.ex"], [Store.PricingTest])
report = Muta.run(config)

report.score                    #=> 87.5
report.killed                   #=> 7
Muta.Report.survivors(report)   #=> [%Muta.Mutant{line: 5, original: "cents > 5000", ...}]
```

`Muta.Config.new/3` takes source file paths and already-loaded test modules.

| Option                 | Default                     | Sets                                                              |
|------------------------|-----------------------------|---------------------------------------------------------------------|
| `:mutators`            | `[Muta.Mutator.Comparison]` | Which mutators to apply.                                           |
| `:baseline_timeout_ms` | `30_000`                    | How long your tests may take before muta stops trusting them.       |

## Writing a mutator

`Muta.Mutator` is one callback. Given a node from your syntax tree, return what
it could become, or `[]` to leave it alone.

```elixir
defmodule Store.Mutator.LogicFlip do
  @behaviour Muta.Mutator

  @impl Muta.Mutator
  def mutations({:and, meta, [left, right]}), do: [{:or, meta, [left, right]}]
  def mutations({:or, meta, [left, right]}), do: [{:and, meta, [left, right]}]
  def mutations(_node), do: []
end
```

```elixir
Muta.Config.new(files, test_modules,
  mutators: [Muta.Mutator.Comparison, Store.Mutator.LogicFlip]
)
```

It is a pure function, so it tests without running anything:

```elixir
test "offers or in place of and" do
  [mutation] = Store.Mutator.LogicFlip.mutations(quote(do: paid? and shipped?))

  assert Macro.to_string(mutation) == "paid? or shipped?"
end
```

> **Note**
> A mutator can only replace nodes that carry line metadata, which means calls,
> operators and blocks. Bare literals such as `42` and `true` are plain terms in
> Elixir's syntax tree with no line attached, so mutating them needs a change to
> how muta parses. That is why there is no literal mutator yet.

## Limits

* You name the tests. muta does not work out which tests cover your code.
* One mutator. Arithmetic and return values are not built yet, and a literal
  mutator needs a change to parsing first.
* Serial. One mutant at a time, in one VM.
* Not on Hex. Install from git.

## Prior art

[Stryker](https://stryker-mutator.io) for the mutator catalogue and the
vocabulary, [mutmut](https://github.com/boxed/mutmut) and
[Pitest](https://pitest.org) for coverage-driven test selection, and
[go-mutesting](https://github.com/zimmski/go-mutesting) for keeping mutators
small and independent.

## License

MIT. See [LICENSE](LICENSE).
