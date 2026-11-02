#!/usr/bin/env bash
set -euo pipefail

OCCT_REPOSITORY="${OCCT_REPOSITORY:-precise-simulation/OCCT}"
TARGET_BRANCH="${TARGET_BRANCH:-netgen-featool}"
UPDATE_BRANCH="${UPDATE_BRANCH:-automation/occt-sdk-update}"
REQUESTED_RELEASE="${REQUESTED_RELEASE:-}"
RETRY_EXISTING="${RETRY_EXISTING:-false}"
RETRY_RELEASE="${RETRY_RELEASE:-false}"
PIN_FILE=".github/occt-sdk-release.txt"
QUALIFICATION_WORKFLOWS=(
  "windows-netgen-sdk.yml"
  "linux-netgen-sdk.yml"
  "macos-netgen-sdk.yml"
)

if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
  echo "GITHUB_REPOSITORY is required." >&2
  exit 1
fi

summary() {
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '%s\n' "$*" >> "$GITHUB_STEP_SUMMARY"
  fi
  printf '%s\n' "$*"
}

release_is_valid() {
  local json="$1"
  jq -e '
    .draft == false and
    .prerelease == false and
    .immutable == true and
    (.tag_name | test("^occt-sdk-[0-9]+\\.[0-9]+\\.[0-9]+(-r[0-9]+)?$"))
  ' >/dev/null <<<"$json"
}

list_immutable_release_tags() {
  gh api --paginate "repos/$OCCT_REPOSITORY/releases?per_page=100" |
    jq -s -r '
      add |
      .[] |
      select(.draft == false and .prerelease == false and .immutable == true) |
      .tag_name |
      select(test("^occt-sdk-[0-9]+\\.[0-9]+\\.[0-9]+(-r[0-9]+)?$"))
    ' |
    sort -V
}

resolve_candidate_release() {
  local current="$1"
  local candidate

  if [[ -n "$REQUESTED_RELEASE" ]]; then
    local requested_json
    requested_json="$(gh api "repos/$OCCT_REPOSITORY/releases/tags/$REQUESTED_RELEASE")"
    if ! release_is_valid "$requested_json"; then
      echo "Requested OCCT release is not a published immutable SDK release: $REQUESTED_RELEASE" >&2
      exit 1
    fi
    candidate="$(jq -r '.tag_name' <<<"$requested_json")"
  else
    mapfile -t tags < <(list_immutable_release_tags)
    if (( ${#tags[@]} == 0 )); then
      echo "No published immutable OCCT SDK releases were found." >&2
      exit 1
    fi
    candidate="${tags[${#tags[@]}-1]}"
    if ! printf '%s\n' "${tags[@]}" | grep -Fxq "$current"; then
      echo "Pinned OCCT SDK release is not present as an immutable published release: $current" >&2
      exit 1
    fi
  fi

  if [[ "$candidate" != "$current" ]]; then
    local greatest
    greatest="$(printf '%s\n%s\n' "$current" "$candidate" | sort -V | tail -n 1)"
    if [[ "$greatest" != "$candidate" ]]; then
      echo "Refusing OCCT SDK downgrade from $current to $candidate." >&2
      exit 1
    fi
  fi

  printf '%s\n' "$candidate"
}

workflow_runs_json() {
  local workflow="$1"
  local ref="$2"
  gh api --method GET "repos/$GITHUB_REPOSITORY/actions/workflows/$workflow/runs" \
    -f event=workflow_dispatch \
    -f branch="$ref" \
    -f per_page=100
}

max_matching_run_id() {
  local workflow="$1"
  local ref="$2"
  local sha="$3"
  workflow_runs_json "$workflow" "$ref" |
    jq -r --arg sha "$sha" '
      [.workflow_runs[] | select(.head_sha == $sha) | .id] | max // 0
    '
}

new_matching_run_id() {
  local workflow="$1"
  local ref="$2"
  local sha="$3"
  local before="$4"
  workflow_runs_json "$workflow" "$ref" |
    jq -r --arg sha "$sha" --argjson before "$before" '
      [.workflow_runs[] | select(.head_sha == $sha and .id > $before)] |
      sort_by(.id) |
      reverse |
      .[0].id // empty
    '
}

qualify_ref() {
  local ref="$1"
  local sha="$2"
  local phase="$3"
  declare -A before=()
  declare -A run_ids=()

  summary "### $phase qualification"
  summary ""
  summary "- Ref: $ref"
  summary "- Commit: $sha"

  local workflow
  for workflow in "${QUALIFICATION_WORKFLOWS[@]}"; do
    before["$workflow"]="$(max_matching_run_id "$workflow" "$ref" "$sha")"
  done

  for workflow in "${QUALIFICATION_WORKFLOWS[@]}"; do
    gh api --method POST "repos/$GITHUB_REPOSITORY/actions/workflows/$workflow/dispatches" \
      -f ref="$ref" >/dev/null
  done

  local deadline=$((SECONDS + 14400))
  local all_complete
  while (( SECONDS < deadline )); do
    all_complete=true
    for workflow in "${QUALIFICATION_WORKFLOWS[@]}"; do
      if [[ -z "${run_ids[$workflow]:-}" ]]; then
        run_ids["$workflow"]="$(new_matching_run_id "$workflow" "$ref" "$sha" "${before[$workflow]}")"
      fi

      if [[ -z "${run_ids[$workflow]:-}" ]]; then
        all_complete=false
        continue
      fi

      local run_json status conclusion
      run_json="$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/${run_ids[$workflow]}")"
      status="$(jq -r '.status' <<<"$run_json")"
      conclusion="$(jq -r '.conclusion // ""' <<<"$run_json")"
      printf '%s: %s %s\n' "$workflow" "$status" "$conclusion"
      if [[ "$status" != "completed" ]]; then
        all_complete=false
      fi
    done

    if [[ "$all_complete" == true ]]; then
      break
    fi
    sleep 30
  done

  if [[ "$all_complete" != true ]]; then
    echo "$phase qualification timed out for $sha." >&2
    return 1
  fi

  local failed=false
  local details=""
  for workflow in "${QUALIFICATION_WORKFLOWS[@]}"; do
    local run_json conclusion url
    run_json="$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/${run_ids[$workflow]}")"
    conclusion="$(jq -r '.conclusion // ""' <<<"$run_json")"
    url="$(jq -r '.html_url' <<<"$run_json")"
    details+="- $workflow: $conclusion - $url"$'\n'
    summary "- $workflow: **$conclusion** - $url"
    if [[ "$conclusion" != "success" ]]; then
      failed=true
    fi
  done

  if [[ "$failed" == true ]]; then
    echo "$phase qualification failed for $sha." >&2
    return 1
  fi
}

qualify_commit() {
  local sha="$1"
  local phase="$2"
  local ref="automation/occt-qualify-${sha:0:12}"

  if git ls-remote --exit-code --heads origin "$ref" >/dev/null 2>&1; then
    git push origin --delete "$ref"
  fi
  git push origin "$sha:refs/heads/$ref"

  local rc=0
  qualify_ref "$ref" "$sha" "$phase" || rc=$?
  git push origin --delete "$ref" || true
  return "$rc"
}

wait_for_release_run() {
  local sha="$1"
  local before="$2"
  local release_tag="$3"
  local deadline=$((SECONDS + 14400))
  local run_id=""

  while (( SECONDS < deadline )); do
    local runs_json
    runs_json="$(gh api --method GET "repos/$GITHUB_REPOSITORY/actions/workflows/release-netgen-sdk.yml/runs" \
      -f event=workflow_dispatch \
      -f branch="$release_tag" \
      -f per_page=100)"
    run_id="$(jq -r --arg sha "$sha" --arg tag "$release_tag" --argjson before "$before" '
      [.workflow_runs[] | select(.head_sha == $sha and .head_branch == $tag and .id > $before)] |
      sort_by(.id) |
      reverse |
      .[0].id // empty
    ' <<<"$runs_json")"
    if [[ -n "$run_id" ]]; then
      local run_json status conclusion
      run_json="$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$run_id")"
      status="$(jq -r '.status' <<<"$run_json")"
      conclusion="$(jq -r '.conclusion // ""' <<<"$run_json")"
      printf 'release-netgen-sdk.yml: %s %s\n' "$status" "$conclusion"
      if [[ "$status" == "completed" ]]; then
        local url
        url="$(jq -r '.html_url' <<<"$run_json")"
        summary ""
        summary "### Netgen SDK release"
        summary ""
        summary "- Workflow: $url"
        summary "- Conclusion: **$conclusion**"
        [[ "$conclusion" == "success" ]]
        return
      fi
    fi
    sleep 30
  done

  echo "Timed out waiting for the Netgen SDK release workflow." >&2
  return 1
}

release_tags_for_sha() {
  local sha="$1"
  local short_sha="${sha:0:12}"
  git ls-remote --tags origin "refs/tags/netgen-sdk-$short_sha-r*" |
    sed -E 's#.*refs/tags/(netgen-sdk-[0-9a-fA-F]{12}-r[0-9]+)(\^\{\})?$#\1#' |
    grep -E "^netgen-sdk-$short_sha-r[0-9]+$" |
    sort -t r -k 2,2n -u || true
}

published_release_for_sha() {
  local sha="$1"
  local prefix="netgen-sdk-${sha:0:12}-r"
  gh api --paginate "repos/$GITHUB_REPOSITORY/releases?per_page=100" |
    jq -s -r --arg prefix "$prefix" '
      add |
      [.[] | select(.draft == false and (.tag_name | startswith($prefix)))] |
      sort_by(.published_at) |
      reverse |
      .[0].tag_name // empty
    '
}

find_automation_merge_for_release() {
  local release="$1"
  git fetch origin "$TARGET_BRANCH" >/dev/null

  local merge_sha
  while IFS= read -r merge_sha; do
    local parents_text
    parents_text="$(git show -s --format=%P "$merge_sha")"
    read -r -a parents <<<"$parents_text"
    if (( ${#parents[@]} != 2 )); then
      continue
    fi

    if ! git log --format=%s "${parents[0]}..${parents[1]}" |
      grep -Fxq "ci: update OCCT SDK to $release"; then
      continue
    fi

    local merge_pin
    merge_pin="$(git show "$merge_sha:$PIN_FILE" | tr -d '\r\n')"
    if [[ "$merge_pin" == "$release" ]]; then
      printf '%s\n' "$merge_sha"
      return 0
    fi
  done < <(git log --first-parent --format=%H -n 100 "origin/$TARGET_BRANCH")

  return 1
}

publish_merge_sha() {
  local merge_sha="$1"

  qualify_commit "$merge_sha" "post-merge exact-SHA"

  local short_sha existing_tags revision release_tag
  short_sha="${merge_sha:0:12}"
  existing_tags="$(release_tags_for_sha "$merge_sha")"
  revision=1
  if [[ -n "$existing_tags" ]]; then
    revision=$(( $(sed -E 's/.*-r([0-9]+)$/\1/' <<<"$existing_tags" | sort -n | tail -n 1) + 1 ))
  fi
  release_tag="netgen-sdk-$short_sha-r$revision"

  git fetch origin "$TARGET_BRANCH"
  git merge-base --is-ancestor "$merge_sha" "origin/$TARGET_BRANCH"
  git tag "$release_tag" "$merge_sha"
  git push origin "$release_tag"

  local before_release
  before_release="$(
    gh api --method GET "repos/$GITHUB_REPOSITORY/actions/workflows/release-netgen-sdk.yml/runs" \
      -f event=workflow_dispatch \
      -f branch="$release_tag" \
      -f per_page=100 |
      jq -r --arg sha "$merge_sha" --arg tag "$release_tag" '
        [.workflow_runs[] | select(.head_sha == $sha and .head_branch == $tag) | .id] | max // 0
      '
  )"

  gh api --method POST "repos/$GITHUB_REPOSITORY/actions/workflows/release-netgen-sdk.yml/dispatches" \
    --input - >/dev/null <<EOF
{"ref":"$release_tag","inputs":{"publish_release":"true"}}
EOF

  summary ""
  summary "- Release tag: $release_tag"
  wait_for_release_run "$merge_sha" "$before_release" "$release_tag"
}

current_release="$(tr -d '\r\n' < "$PIN_FILE")"
if [[ ! "$current_release" =~ ^occt-sdk-[0-9]+\.[0-9]+\.[0-9]+(-r[0-9]+)?$ ]]; then
  echo "Invalid current OCCT SDK release pin: $current_release" >&2
  exit 1
fi

candidate_release="$(resolve_candidate_release "$current_release")"
summary "## Automatic OCCT -> Netgen SDK update"
summary ""
summary "- Current OCCT SDK: $current_release"
summary "- Latest selected OCCT SDK: $candidate_release"

if [[ "$candidate_release" == "$current_release" ]]; then
  pending_merge="$(find_automation_merge_for_release "$current_release" || true)"
  if [[ -z "$pending_merge" ]]; then
    summary "- Result: no update required."
    exit 0
  fi

  published_release="$(published_release_for_sha "$pending_merge")"
  if [[ -n "$published_release" ]]; then
    summary "- Result: no update required; $published_release already publishes the automated OCCT update."
    exit 0
  fi

  pending_tags="$(release_tags_for_sha "$pending_merge")"
  if [[ -n "$pending_tags" && "$RETRY_RELEASE" != "true" ]]; then
    summary "- Automated OCCT merge $pending_merge has no published SDK, but release tag(s) already exist:"
    while IFS= read -r tag; do
      [[ -n "$tag" ]] && summary "  - $tag"
    done <<<"$pending_tags"
    summary "- Result: release retry requires manual dispatch with retry_release=true; no new tag was created."
    exit 1
  fi

  summary "- Resuming unpublished automated OCCT merge: $pending_merge"
  publish_merge_sha "$pending_merge"
  exit 0
fi

head_sha=""
if git ls-remote --exit-code --heads origin "$UPDATE_BRANCH" >/dev/null 2>&1; then
  git fetch origin "$UPDATE_BRANCH:refs/remotes/origin/$UPDATE_BRANCH"
  git fetch origin "$TARGET_BRANCH:refs/remotes/origin/$TARGET_BRANCH"
  head_sha="$(git rev-parse "origin/$UPDATE_BRANCH")"
  update_subject="$(git show -s --format=%s "$head_sha")"
  if [[ "$update_subject" != "ci: update OCCT SDK to $candidate_release" ]]; then
    echo "Existing automation branch has unexpected head subject: $update_subject" >&2
    exit 1
  fi

  read -r -a update_commit_fields <<<"$(git rev-list --parents -n 1 "$head_sha")"
  if (( ${#update_commit_fields[@]} != 2 )); then
    echo "Existing automation branch head must be a single-parent generated pin commit." >&2
    exit 1
  fi
  update_parent="${update_commit_fields[1]}"
  if ! git merge-base --is-ancestor "$update_parent" "origin/$TARGET_BRANCH"; then
    echo "Existing automation branch parent is not contained in $TARGET_BRANCH." >&2
    exit 1
  fi

  mapfile -t update_paths < <(git diff-tree --no-commit-id --name-only -r "$head_sha")
  if (( ${#update_paths[@]} != 1 )) || [[ "${update_paths[0]}" != "$PIN_FILE" ]]; then
    echo "Existing automation branch is not a pin-only generated update." >&2
    exit 1
  fi

  branch_pin="$(
    gh api --method GET "repos/$GITHUB_REPOSITORY/contents/$PIN_FILE" -f ref="$UPDATE_BRANCH" |
      jq -r '.content' |
      tr -d '\n' |
      base64 --decode |
      tr -d '\r\n'
  )"
  if [[ "$branch_pin" != "$candidate_release" ]]; then
    echo "Existing automation branch $UPDATE_BRANCH pins $branch_pin, not $candidate_release. Resolve or delete it before a newer update can proceed." >&2
    exit 1
  fi
  if [[ "$RETRY_EXISTING" != "true" ]]; then
    summary "- Existing update branch: $UPDATE_BRANCH"
    summary "- Result: existing failed/incomplete update is left for inspection; use manual dispatch with retry_existing=true to re-run qualification."
    exit 0
  fi
else
  git fetch origin "$TARGET_BRANCH"
  base_sha="$(git rev-parse FETCH_HEAD)"

  git checkout -B "$UPDATE_BRANCH" "$base_sha"
  printf '%s\n' "$candidate_release" > "$PIN_FILE"
  git add "$PIN_FILE"
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  git commit -m "ci: update OCCT SDK to $candidate_release"
  head_sha="$(git rev-parse HEAD)"
  git push origin "HEAD:refs/heads/$UPDATE_BRANCH"
fi

qualify_ref "$UPDATE_BRANCH" "$head_sha" "pre-merge OCCT update"

git fetch origin "$TARGET_BRANCH:refs/remotes/origin/$TARGET_BRANCH"
target_sha="$(git rev-parse "origin/$TARGET_BRANCH")"
merge_base="$(git merge-base "$head_sha" "$target_sha")"
if [[ "$merge_base" != "$target_sha" ]]; then
  echo "The target branch advanced after the update branch was prepared. Recreate the automation branch, then manually dispatch with retry_existing=true." >&2
  exit 1
fi

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git checkout --detach "$target_sha"
git merge --no-ff "$head_sha" \
  -m "Merge automated OCCT SDK update $candidate_release" \
  -m "ci: update OCCT SDK to $candidate_release"
merge_sha="$(git rev-parse HEAD)"

if ! git push origin "$merge_sha:refs/heads/$TARGET_BRANCH"; then
  echo "Atomic push of qualified merge commit was rejected because the target moved or rejected the update. Recreate the update branch and retry." >&2
  exit 1
fi

git push origin --delete "$UPDATE_BRANCH" || true
summary ""
summary "### Merge"
summary ""
summary "- Merge commit: $merge_sha"

publish_merge_sha "$merge_sha"
