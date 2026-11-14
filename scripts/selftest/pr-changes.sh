#!/usr/bin/env bash
# Run the classifier step of pr-changes.yml (extracted, not copied) on
# synthetic pull requests: a repository with a base branch, a pull request
# branch and the merge commit GitHub would test, cloned with the depth the
# workflow fetches. Documentation-only pull requests give full=false; every
# other change, and every case the classifier cannot be sure of, full=true.
set -euo pipefail
cd "$(dirname "$0")/../.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 scripts/selftest/extract-step.py .github/workflows/pr-changes.yml "Classify changed files" > "$tmp/classify.py"

export GIT_AUTHOR_NAME=selftest GIT_AUTHOR_EMAIL=selftest@example.invalid
export GIT_COMMITTER_NAME=selftest GIT_COMMITTER_EMAIL=selftest@example.invalid
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# pr <main change or -> <pull request change>: builds $tmp/clone, the merge
# commit of the pull request into main, fetched with depth 2 as actions/checkout
# does; sets HEAD_SHA to the pull request head.
pr() {
  rm -rf "$tmp/repo" "$tmp/clone"
  git init -q -b main "$tmp/repo"
  (
    cd "$tmp/repo"
    mkdir -p docs/gen sub .github/workflows testdata vendor/x
    for f in README.md AGENTS.md docs/a.md docs/gen/objects.md sub/README.md sub/CLAUDE.md \
      testdata/fixture.md vendor/x/README.md .github/workflows/ci.yml .github/pull_request_template.md; do
      echo "base $f" > "$f"
    done
    printf 'package main\n\nfunc main() {}\n' > main.go
    git add -A && git commit -q -m base
    git switch -q -c pr
    eval "$2"
    git add -A && git commit -q --allow-empty -m head
    git switch -q main
    if [ "$1" != - ]; then eval "$1"; git add -A && git commit -q -m "main moves on"; fi
    git merge -q --no-ff --no-edit pr
  )
  HEAD_SHA=$(git -C "$tmp/repo" rev-parse pr)
  git clone -q --depth 2 "file://$tmp/repo" "$tmp/clone"
}

# classify <dir> VAR=value...  ->  $tmp/out (GITHUB_OUTPUT), $tmp/log
classify() {
  local dir=$1
  shift
  : > "$tmp/out"
  (cd "$dir" && env EVENT=pull_request HEAD_SHA="$HEAD_SHA" CODE_PATHS= GITHUB_OUTPUT="$tmp/out" \
    GITHUB_STEP_SUMMARY="$tmp/summary" "$@" python3 -I "$tmp/classify.py") > "$tmp/log" 2>&1 \
    || { echo "FAIL: the classifier exited non-zero"; cat "$tmp/log"; exit 1; }
}

# expect <name> <want full> <text in reason or ->
expect() {
  local name=$1 want=$2 text=$3
  [ "$(grep -c '^full=' "$tmp/out")" = 1 ] || { echo "FAIL $name: not exactly one full= line"; cat "$tmp/out"; exit 1; }
  grep -qx "full=$want" "$tmp/out" || { echo "FAIL $name: want full=$want"; cat "$tmp/out" "$tmp/log"; exit 1; }
  if [ "$text" != - ] && ! grep -q "^reason=.*$text" "$tmp/out"; then
    echo "FAIL $name: reason does not say '$text'"; cat "$tmp/out"; exit 1
  fi
  echo "ok   $name: full=$want"
}

# case <name> <want full> <reason text> <main change> <pull request change> [VAR=value...]
case_() {
  local name=$1 want=$2 text=$3 main=$4 change=$5
  shift 5
  pr "$main" "$change"
  classify "$tmp/clone" "$@"
  expect "$name" "$want" "$text"
}

# Documentation only.
case_ "README"                       false "documentation" - 'echo x >> README.md'
case_ "Markdown under docs/"         false "documentation" - 'echo x >> docs/a.md'
case_ "new Markdown file"            false "documentation" - 'echo x > docs/new.md'
case_ "README of a nested module"    false "documentation" - 'echo x >> sub/README.md'
case_ "several documents"            false "all 3 changed" - 'echo x >> README.md; echo x >> docs/a.md; echo x > docs/b.md'
case_ "main moved on with code"      false "documentation" 'echo "// x" >> main.go' 'echo x >> README.md'

# Code, or not sure.
case_ "Go source"                    true "not Markdown" - 'echo "// x" >> main.go'
case_ "documents and code"           true "1 of 2" - 'echo x >> README.md; echo "// x" >> main.go'
case_ "workflow"                     true "not Markdown" - 'echo "# x" >> .github/workflows/ci.yml'
case_ "Markdown in .github"          true "dot directory" - 'echo x >> .github/pull_request_template.md'
case_ "AGENTS.md"                    true "agent instructions" - 'echo x >> AGENTS.md'
case_ "nested CLAUDE.md"             true "agent instructions" - 'echo x >> sub/CLAUDE.md'
case_ "Markdown fixture"             true "fixture" - 'echo x >> testdata/fixture.md'
case_ "vendored Markdown"            true "vendored" - 'echo x >> vendor/x/README.md'
case_ "upper-case extension"         true "not Markdown" - 'echo x > docs/NOTES.MD'
case_ "deleted document"             true "status D" - 'git rm -q docs/a.md'
case_ "renamed document"             true "status D" - 'git mv docs/a.md docs/b.md'
case_ "symlink named .md"            true "not a regular file" - 'ln -s ../main.go docs/link.md'
case_ "executable Markdown"          true "not a regular file" - 'chmod +x docs/a.md'
case_ "file becomes a symlink"       true "status T" - 'rm docs/a.md; ln -s README.md docs/a.md'
case_ "README listed in code-paths"  true "code-paths" - 'echo x >> README.md' CODE_PATHS=$'# read by readme_test.go\nREADME.md'
case_ "glob in code-paths"           true "code-paths" - 'echo x >> docs/gen/objects.md' CODE_PATHS='docs/gen/*.md'
case_ "code-paths match whole paths" false "documentation" - 'echo x >> sub/README.md' CODE_PATHS='README.md'
case_ "a newline in a file name"     true "not Markdown" - 'printf x > "$(printf "x\nfull=false.go")"'
case_ "nothing changes"              true "changes no files" 'echo same >> docs/a.md' 'echo same >> docs/a.md'

# The checkout is not what the classifier expects.
pr - 'echo x >> README.md'
classify "$tmp/clone" EVENT=push
expect "not a pull request event"    true "push event"
classify "$tmp/clone" HEAD_SHA=0000000000000000000000000000000000000000
expect "head is not the second parent" true "second parent"
classify "$tmp/clone" HEAD_SHA=
expect "no head in the event"        true "second parent"
git -C "$tmp/clone" fetch -q --depth 1 origin pr && git -C "$tmp/clone" checkout -q FETCH_HEAD
classify "$tmp/clone"
expect "HEAD is not a merge commit"  true "not the two"
mkdir "$tmp/nogit"
classify "$tmp/nogit"
expect "git fails"                   true "classification failed"
echo "pr changes: all cases match"
