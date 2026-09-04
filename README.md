# asdf-format Tap

Homebrew formulae for the [ASDF](https://www.asdf-format.org/) project.

## Formulae

| Formula | Description |
| ------- | ----------- |
| [`libasdf`](Formula/libasdf.rb) | C implementation of the ASDF file format ([docs](https://libasdf.readthedocs.io/), [source](https://github.com/asdf-format/libasdf)) |

## Installation

```sh
brew install asdf-format/tap/<formula>
```

Or tap first, then install by short name:

```sh
brew tap asdf-format/tap
brew install <formula>
```

Or, in a `brew bundle` `Brewfile`:

```ruby
tap "asdf-format/tap"
brew "<formula>"
```

### A note on `libasdf` and the `asdf` command

`libasdf` installs an `asdf` command-line tool, which collides with the
[asdf version manager](https://asdf-vm.com/) formula in homebrew-core. The
formula therefore declares `conflicts_with "asdf"`; the two cannot be linked at
the same time.

### Platform support

Bottles (pre-built binaries) are published for Apple Silicon macOS and x86-64
Linux. Intel macOS is **not** bottled: Homebrew [discontinued Intel macOS
bottle CI in August 2026](https://github.com/orgs/Homebrew/discussions/7044)
and moved that configuration to [Tier
3](https://docs.brew.sh/Support-Tiers#tier-3) -- "not supported", with no CI
coverage. Installing on an Intel Mac still works, but Homebrew will build
`libasdf` and any unbottled dependencies from source, which is slow but
otherwise unremarkable.

## Maintainer guide

The canonical reference is
[How to Create and Maintain a Tap](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap).
What follows is the short version, plus the parts that are easy to get wrong.

### The one thing to know

**Never merge a formula pull request with GitHub's merge button.**

A formula's `bottle do` block contains SHA-256 checksums of binaries that only
exist *after* CI has built them. So the formula on `main` cannot be correct
until merge time, and GitHub's merge button cannot rewrite a commit to add
them. Homebrew replaces the merge button with `brew pr-pull`, which does all of
this in one operation:

1. fetch the pull request's commits
2. download the `bottles_*` artifacts that CI uploaded for that PR
3. upload those bottles to their hosting (see below)
4. rewrite the formula commit to insert the `bottle do` block
5. cherry-pick the rewritten commits onto `main`

Note that it stops there -- **it does not push, and it does not "merge" the PR**
in GitHub's sense. There is no merge commit; the PR's commits are replayed onto
`main`, and GitHub marks the PR merged once those commits are pushed.

### Bumping a formula to a new upstream release

```sh
brew bump-formula-pr --version=<new-version> asdf-format/tap/<formula>
```

This forks the tap if needed, updates `url` and `sha256`, pushes a branch, and
opens the PR. Do not hand-edit the version: it is derived from the URL, and
`bump-formula-pr` rewrites those stanzas automatically--any attempt to do it
by hand is overwritten anyways.

Then check CI:

```sh
gh pr checks <number> --watch
```

### Landing a pull request (and publishing bottles)

Add the **`pr-pull`** label to the PR. `.github/workflows/publish.yml` then runs
`brew pr-pull` and pushes the result. That is the whole flow.

To do it by hand instead -- which is also the recovery path when the workflow
misbehaves:

```sh
cd "$(brew --repository asdf-format/tap)"
brew pr-pull --tap=asdf-format/tap <number>
git push origin main
```

The `git push` is not optional; it is what closes the PR.

### Where bottles are hosted

GitHub Releases on this repository, one release per formula version, tagged
`<formula>-<version>` (e.g. `libasdf-0.1.0`). `brew pr-pull` creates the
release and attaches the bottles automatically. This is Homebrew's default for
third-party taps; no extra credentials or configuration are required.

### Continuous integration

- `.github/workflows/tests.yml` -- runs `brew test-bot` on every PR: syntax,
  audit, build, `brew test`, and bottle creation. Bottles are uploaded as
  `bottles_<os>` artifacts.
- `.github/workflows/publish.yml` -- runs `brew pr-pull` when the `pr-pull`
  label is added.

Beware a sharp edge in `brew test-bot`: if any dependency lacks a bottle for
the runner's platform, it **skips** the formula and still reports success. Watch
for `SKIPPED` in the log, or check the `skipped_or_failed_formulae-*.txt` file
it writes, since a green check does not by itself prove the formula was built.

This may have only come up due to homebrew-core's very recent as of writing
sunsetting of macos-intel support, so it shouldn't come up too often anymore
for now.

### Testing a formula locally

```sh
brew install --build-from-source asdf-format/tap/<formula>
brew test asdf-format/tap/<formula>
brew audit --strict --online --formula asdf-format/tap/<formula>
brew style asdf-format/tap/<formula>
```

`brew style --fix` autocorrects most formatting complaints.

## Documentation

`brew help`, `man brew`, or [Homebrew's documentation](https://docs.brew.sh).
