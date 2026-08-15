<p align="center">
	<img src=".assets/logo.svg" alt="" width="96">
</p>

<h1 align="center">muta</h1>

<p align="center">
	Mutation testing for Elixir, fast enough to run before every commit.
</p>

<p align="center">
	<img src="https://img.shields.io/badge/elixir-~%3E%201.20-4B275F" alt="Elixir ~> 1.20">
	<img src="https://img.shields.io/badge/status-alpha-F0A500" alt="Status: alpha">
	<img src="https://img.shields.io/badge/license-MIT-6E4A7E" alt="License: MIT">
</p>

---

Your tests cover the line. That does not mean they pin what it does.

muta changes your code in small ways, re-runs the tests that cover the change,
and reports every change no test noticed:

```
  lib/store/pricing.ex:5
    - cents > 5000
    + cents >= 5000
    survived
```

Free shipping over $50 can become free shipping at exactly $50 and the whole
suite stays green. Nobody tested a cart at 5000 cents.

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

3. Ignore the coverage cache:

	```gitignore
	.muta/
	```

## Usage

```shell
mix mutate                        # your staged .ex files
mix mutate lib/store/pricing.ex   # or whatever you name
```

```
$ mix mutate lib/store/pricing.ex
Mutating lib/store/pricing.ex

  lib/store/pricing.ex:5
    - cents > 5000
    + cents >= 5000
    survived

8 mutants · 7 killed · 1 survived · 0 invalid · 87.5%
```

| Outcome      | Means                                                                 |
|--------------|-------------------------------------------------------------------------|
| **killed**   | A test failed. That behaviour is pinned.                                |
| **survived** | Every test passed. Nothing pins it. This is the output you act on.      |
| **invalid**  | The compiler rejected the change. Left out of the score.                |

It exits `1` when anything survived and `0` when nothing did, so it drops
straight into a pre-commit hook.

The first run maps which tests reach which functions and caches it under
`.muta/`. On a Phoenix app with about 1,900 tests that takes 90 seconds. Every
run after it is under two.

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

| It finds                                                     | Because                                                                     |
|----------------------------------------------------------------|-------------------------------------------------------------------------------|
| A test failing on your unmutated code                          | Every mutant would look killed and the score would look perfect.             |
| Two runs of your suite disagreeing                             | A suite that leaks state kills mutants for reasons unrelated to the mutation. |
| A process still running a mutant after its test finished       | The next mutant would be judged partly against this one.                     |
| A target compiled without debug info                           | Which tests reach it is unknowable, so every mutant would look like a survivor. |
| Your unmutated suite not finishing in `:baseline_timeout_ms`   | There is no honest deadline to hold a mutant to.                             |

## Why it is fast

The usual design copies your project to a temp directory, applies the mutation
on disk, shells out to `mix test`, and reads stdout. That is a compile and a VM
boot for every mutant.

muta stays in the BEAM you are already running:

```
source → AST → mutate one node → Code.compile_quoted → :code.load_binary
       → ExUnit.run/1 on the covering tests → restore the original binary
```

Two things do the work. A mutant is loaded rather than written, which costs
milliseconds. And only the covering tests run, closest test module first, so
most mutants die in one small run.

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

| `Muta.Config.new/3` option | Default                     | Sets                                                             |
|----------------------------|-----------------------------|--------------------------------------------------------------------|
| `:mutators`                | `[Muta.Mutator.Comparison]` | Which mutators to apply.                                          |
| `:baseline_timeout_ms`     | `30_000`                    | How long your unmutated suite may take before muta stops trusting it. |
| `:load_test_module`        | assumes loaded              | Called before muta needs a test module, so a run can require test files lazily. |

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

It is a pure function, so it tests without running anything. Domain mutators
are worth writing. One that drops a tenancy scope or flips an authorization
check tells you something no generic operator can.

## Limits

* Serial. One mutant at a time, in one VM.
* One mutator. Arithmetic and return values are not built yet.
* Bare literals like `42` and `true` carry no line in Elixir's syntax tree, so
  a literal mutator needs a change to how muta parses.
* Single Mix project. No umbrella support.
* The cache is keyed to the files you mutate, so a file you have not mutated
  before pays for a rebuild.
* Not on Hex. Install from git.

## Prior art

[Stryker](https://stryker-mutator.io) for the mutator catalogue and the
vocabulary, [mutmut](https://github.com/boxed/mutmut) and
[Pitest](https://pitest.org) for coverage-driven test selection, and
[go-mutesting](https://github.com/zimmski/go-mutesting) for keeping mutators
small and independent.

## License

MIT. See [LICENSE](LICENSE).
