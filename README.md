<p align="center">
	<img src=".assets/logo.svg" alt="" width="96">
</p>

<h1 align="center">muta</h1>

<p align="center">
	Mutation testing for Elixir. Name the code and the tests, and it tells you what the tests miss.
</p>

<p align="center">
	<a href="https://hex.pm/packages/muta"><img src="https://img.shields.io/hexpm/v/muta?color=4B275F" alt="Hex version"></a>
	<a href="https://hexdocs.pm/muta"><img src="https://img.shields.io/badge/hexdocs-muta-6E4A7E" alt="HexDocs"></a>
	<img src="https://img.shields.io/badge/elixir-~%3E%201.20-4B275F" alt="Elixir ~> 1.20">
	<img src="https://img.shields.io/badge/status-alpha-F2A63C" alt="Status: alpha">
	<img src="https://img.shields.io/badge/license-MIT-6E4A7E" alt="License: MIT">
</p>

> **Experimental.** muta is alpha. Expect the API to change between releases,
> and expect rough edges: it has been used seriously on one codebase so far.
> Read [Limits](#limits) before you rely on it.

Tests can cover every line of a function without checking what it actually does.
muta makes small changes to your code, runs the tests you named, and reports the
changes no test caught:

```
  survived  lib/store/pricing.ex:5  Comparison
    - cents > 5000
    + cents >= 5000
```

Free shipping over $50 is now free shipping at exactly $50, and the suite is
still green, because no test uses a cart of exactly 5000 cents.

## Install

```elixir
{:muta, "~> 0.1", only: [:dev, :test]}
```

muta runs your tests, so the task needs the test environment:

```elixir
def cli do
  [preferred_envs: [mutate: :test]]
end
```

## Running it

Give it source files to mutate and test files to judge them by. Both flags
repeat.

```shell
mix mutate lib/store/pricing.ex --test test/store/pricing_test.exs
```

```
Mutating lib/store/pricing.ex
Judged by test/store/pricing_test.exs

  survived  lib/store/pricing.ex:5  Comparison
    - cents > 5000
    + cents >= 5000

8 mutants · 7 killed · 1 survived · 0 unstable · 0 invalid · 87.5%
```

Name more than one source file and you also get a line per file, so you can see
which one is weak instead of one blended number. Files muta found nothing to
mutate in are listed too:

```
  lib/store/pricing.ex  8 mutants · 7 killed · 1 survived · 0 unstable · 0 invalid · 87.5%
  lib/store/cart.ex  no mutants, so nothing here was checked

8 mutants · 7 killed · 1 survived · 0 unstable · 0 invalid · 87.5%

1 of the 2 files you named produced no mutants and went unchecked.
The score above says nothing about them.
```

## Reading the output

Every finding is `outcome  file:line  mutator`, and there are four outcomes:

| Outcome      | Means                                                       | You        |
|--------------|-------------------------------------------------------------|------------|
| **killed**   | A test failed, twice. That behaviour is pinned.             | do nothing |
| **survived** | Every test passed. Nothing pins it.                         | add a test |
| **accepted** | Survived, and you recorded why no test could kill it.       | do nothing |
| **unstable** | A test failed, then passed on the re-run.                   | see below  |
| **invalid**  | The mutated code didn't compile, so no test ran against it. | do nothing |

The score is killed / (killed + survived). The other three never produced a
verdict you can act on, so they stay out of it. Exit code is `0` when nothing
survived, `1` when anything survived or came back unstable, and `2` when muta
wouldn't score the run at all.

Repeats of one mutation are collapsed, so ten sites sharing a pattern read as
one finding across ten lines rather than ten findings. And when every mutant
inside a function survives, muta says so by name: that usually means the test
files you named don't reach that function at all, which is a different problem
from a weak assertion.

muta runs your tests twice before recording a kill. Tests fail for reasons that
have nothing to do with the mutation, and a false kill makes the score look
better than it is. When the first run fails and the second passes you get
**unstable**, which means your suite gave two answers about the same mutant.
Re-run it, drop `--workers`, or fix the flaky test.

## Mutants no test can kill

Some mutants are **equivalent**: the change is real but nothing observable
differs, so no test can catch them. `>= now` where `now` was read inside the
function; a filter that only narrows what a later exact check re-tests. This is
a known, undecidable problem in mutation testing, and equivalent mutants run
4-39% of all mutants in real code. Nobody scores 100%.

Left alone they make the exit code useless, because the same survivors fail
every run forever. Record them in `muta.exs` instead:

```elixir
[
  %{
    file: "lib/store/pricing.ex",
    original: "cents > 5000",
    mutated: "cents >= 5000",
    reason: "no caller can produce a cart at exactly 5000"
  }
]
```

They still show in the report with the reason attached, and they stop failing
the run. The reason is required, because an accepted mutant is a claim that no
test could ever kill it and the next reader has to be able to check that claim.
Matching is on the expression, not the line, so edits above it don't stale the
record. muta names any entry that matched nothing in the run, since a stale one
will silently accept a real survivor later.

## Only the lines you changed

A whole context module can take minutes. When you're reviewing a change, mutate
what changed:

```shell
mix mutate lib/store/pricing.ex --test test/store/pricing_test.exs --since HEAD
```

The report says how many mutants fell outside those lines, so a scoped run is
never mistaken for a full one.

## You pick the tests

muta judges each mutant only against the test files you name. A survivor means
those tests didn't catch it, not that nothing in your suite would. Name too few
and you'll chase survivors some other test already kills.

That's deliberate. Guessing from filenames assumes a layout, static call graphs
fall apart at protocols and LiveView callbacks, and building a runtime coverage
map costs a full serialised run of the suite first.

## With Claude Code

Working out which tests exercise a file is something an agent is good at. Put
this in your `CLAUDE.md`:

````markdown
## Mutation testing

Before committing, mutation-test the staged source files:

```shell
mix mutate <source file> --test <its test files>
```

Read the diff, work out which test files exercise each staged source file, then
run one command per file so each gets its own score. Run them in parallel.

Exit `0` is clean, `1` needs attention, `2` means muta wouldn't score the run and
the report says why. Each finding reads `outcome  file:line  mutator`:

- `survived` is a missing assertion. Add the assertion. Never delete the mutant
  or loosen the code to make it pass.
- `unstable` means a test failed then passed on the re-run, so the failure wasn't
  the mutation's doing. Re-run once. If it repeats, the flaky test is the bug.
- `invalid` means the mutated code didn't compile. Nothing to fix.

A file reported as `no mutants` wasn't checked at all. The score says nothing
about it, so don't read a pass as covering it.

Skip files defining a `defguard` or `defmacro`, which muta won't mutate.
````

Wrap it in a skill if you'd rather trigger it by hand than on every commit.

## Mutators

Eight, all on by default.

| Mutator                                          | Turns                                                       |
|--------------------------------------------------|-------------------------------------------------------------|
| [`Comparison`](https://github.com/fabioelizandro/muta/blob/main/lib/muta/mutator/comparison.ex)   | `a < b` → `a <= b`, `a < b` → `a > b`, `a == b` → `a != b`  |
| [`Condition`](https://github.com/fabioelizandro/muta/blob/main/lib/muta/mutator/condition.ex)     | `if x do` → `if true do`, then → `if false do`              |
| [`Result`](https://github.com/fabioelizandro/muta/blob/main/lib/muta/mutator/result.ex)           | `:ok` → `:error`, `{:error, r}` → `{:ok, r}`                |
| [`Boolean`](https://github.com/fabioelizandro/muta/blob/main/lib/muta/mutator/boolean.ex)         | `true` → `false`                                            |
| [`Logical`](https://github.com/fabioelizandro/muta/blob/main/lib/muta/mutator/logical.ex)         | `a and b` → `a or b`, `a && b` → `a \|\| b`, `!a` → `a`      |
| [`Arithmetic`](https://github.com/fabioelizandro/muta/blob/main/lib/muta/mutator/arithmetic.ex)   | `a + b` → `a - b`, `a * b` → `a / b`                        |
| [`Membership`](https://github.com/fabioelizandro/muta/blob/main/lib/muta/mutator/membership.ex)   | `a in b` → `a not in b`                                     |
| [`Counterpart`](https://github.com/fabioelizandro/muta/blob/main/lib/muta/mutator/counterpart.ex) | `Enum.filter` → `Enum.reject`, `String.upcase` → `downcase` |

Look at surviving `Condition` mutants first. A surviving `if true` is a branch no
test goes near, and line coverage still calls that branch covered.

Nothing inside `@spec`, `@type`, `@doc`, `@impl` and friends gets mutated. Those
never reach runtime so no test could tell, and each one would come back as a
survivor you can't do anything about. On a codebase of 183 files that was 86
findings.

## Speed

muta compiles a mutant and loads it into the running VM instead of writing it to
disk, which costs about 79ms for a 400-line module:

```
source → AST → mutate one node → Code.compile_quoted → :code.load_binary
       → ExUnit.run/1 on your tests → restore the original binary
```

Mutants are judged in parallel, one worker VM each, because the code server
holds one version of a module at a time. Workers pull from a shared queue, since
a killed mutant costs a fraction of a second and a survivor costs a full run of
your tests.

On a Phoenix app with roughly 1,900 tests, at the default four workers:

| Module under mutation     | Mutants | Time  |
|---------------------------|---------|-------|
| a small value module      | 9       | 3.8s  |
| a webhook parser          | 27      | 3.4s  |
| a context full of queries | 144     | 108s  |

That 144-mutant run takes 269s with `--workers 1` and 102s with `--workers 8`.

Four is the default because there's little left to gain past it. More workers
means more contention, and a test that gets slow enough under load trips its own
timeout, which muta can only read as the mutant dying. Verdicts have drifted by
a mutant or two between repeat runs at higher worker counts, usually between
`survived` and `unstable`. Use `--workers 1` when you need the same number
twice.

## When muta stops instead of scoring

A score you can't trust reads as reassurance, so muta raises
`Muta.UntrustworthyError` rather than print one, when:

* a test fails on your unmutated code, so every mutant would look killed
* two runs of your tests disagree, so kills mean nothing
* a worker's tests are red though yours are green, so its VM is set up wrong
* a process is still running a mutant after its test finished, so the next
  mutant would be judged partly against this one
* your tests don't finish in `:baseline_timeout_ms`, so there's no honest
  deadline to hold a mutant to

## Programmatic use

```elixir
config = Muta.Config.new(["lib/store/pricing.ex"], ["test/store/pricing_test.exs"])
report = Muta.run(config)

report.score                    #=> 87.5
Muta.Report.survivors(report)   #=> [%Muta.Mutant{line: 5, original: "cents > 5000", ...}]
```

muta loads the test files itself, once here and again in every worker, so pass
each one once and don't pass anything `test_helper.exs` already requires. It
calls `Node.start/2` if the VM isn't alive, since the workers need distribution.

| Option                 | Default                | Sets                                               |
|------------------------|------------------------|-----------------------------------------------------|
| `:workers`             | `4`                    | Worker VMs judging at once.                        |
| `:mutators`            | all eight              | Which mutators to apply.                           |
| `:test_helper`         | `test/test_helper.exs` | What each worker requires before your tests.       |
| `:baseline_timeout_ms` | `30_000`               | How long your tests may take before muta gives up. |
| `:acceptances_file`    | `muta.exs`             | Where accepted equivalent mutants are recorded.    |
| `:since`               | the whole file         | A git ref; mutate only lines changed since it.     |

## Writing a mutator

There's one callback. Given a node, return what it could become, or `[]` to
leave it alone.

```elixir
defmodule Store.Mutator.Concat do
  @behaviour Muta.Mutator

  @impl Muta.Mutator
  def mutations({:<>, meta, [left, right]}), do: [{:<>, meta, [right, left]}]
  def mutations(_node), do: []
end
```

Pass it in `mutators:`, and test it without running anything:

```elixir
test "offers the halves the other way round" do
  [mutation] = Store.Mutator.Concat.mutations(quote(do: first <> last))

  assert Macro.to_string(mutation) == "last <> first"
end
```

muta wraps atoms as `{:__block__, meta, [atom]}` so `:ok` and `true` carry their
line. Match that shape to mutate them, like
[`Result`](https://github.com/fabioelizandro/muta/blob/main/lib/muta/mutator/result.ex). The wrapper comes off before anything
compiles.

## Limits

* You name the tests. muta won't work them out.
* Some survivors are unkillable. An `:ok` returned from a function nobody reads
  the result of can't be caught by any test, so go after the survivors that mean
  something rather than the number.
* muta can't usefully mutate its own engine. The mutant loads into the VM doing
  the judging, so it either breaks the run or never gets called. Its pure
  modules mutation-test fine; `Engine`, `Worker` and `Fleet` don't.
* No numbers or strings yet. Integer literals are next, and skipped for now
  because timeouts, HTTP statuses and list indexes make most of them noise.
* A module defining a `defguard` or `defmacro` is refused. Callers already
  compiled the expansion, so they'd never run the mutant.
* Mutants a macro rejects while expanding count as invalid. Ecto query bindings
  (`from b in Booking`) are the usual case.

## Prior art

[Stryker](https://stryker-mutator.io) for the mutator catalogue,
[Pitest](https://pitest.org) for the return-value mutators, and
[go-mutesting](https://github.com/zimmski/go-mutesting) for keeping mutators
small and independent.

## License

MIT. See [LICENSE](LICENSE).
