#!/usr/bin/env bash
set -euo pipefail

# my-prs: Find open PRs that need my personal attention
# - Personal review requests (not team-based)
# - Mentioned in unresolved comment threads
# - My PRs with unresolved review comments

# --- Date calculation ---
RANGE="${1:-1 week}"
NUM=$(echo "$RANGE" | grep -oE '[0-9]+')
UNIT=$(echo "$RANGE" | grep -oE '(day|week|month)s?')
UNIT="${UNIT%s}"

case "$UNIT" in
  day)   DAYS=$NUM ;;
  week)  DAYS=$((NUM * 7)) ;;
  month) DAYS=$((NUM * 30)) ;;
  *)     echo "Usage: my-prs [\"N days|weeks|months\"]" >&2; exit 1 ;;
esac

if date --version &>/dev/null; then
  START_DATE=$(date -d "-${DAYS} days" +%Y-%m-%d)
else
  START_DATE=$(date -v-${DAYS}d +%Y-%m-%d)
fi

USERNAME=$(gh api user --jq '.login')

# Temp file for collecting results (repo|number|title|reason), deduped by repo#number
RESULTS=$(mktemp)
SEEN=$(mktemp)
trap 'rm -f "$RESULTS" "$SEEN"' EXIT

add_result() {
  local repo="$1" number="$2" title="$3" reason="$4"
  local key="${repo}#${number}"
  if ! grep -qxF "$key" "$SEEN" 2>/dev/null; then
    echo "$key" >> "$SEEN"
    echo "${repo}|${number}|${title}|${reason}" >> "$RESULTS"
  fi
}

# 1) Personal review requests
REVIEW_DATA=$(gh api graphql -f query="
{
  search(query: \"is:pr is:open review-requested:${USERNAME} created:>=${START_DATE}\", type: ISSUE, first: 100) {
    nodes {
      ... on PullRequest {
        number
        title
        repository { nameWithOwner }
        reviewRequests(first: 20) {
          nodes {
            requestedReviewer {
              ... on User { login }
              ... on Team { slug }
            }
          }
        }
      }
    }
  }
}")

while IFS=$'\t' read -r repo number title; do
  [[ -z "$number" ]] && continue
  add_result "$repo" "$number" "$title" "review requested"
done < <(echo "$REVIEW_DATA" | jq -r --arg user "$USERNAME" '
  .data.search.nodes[]
  | select(.reviewRequests.nodes | map(select(.requestedReviewer.login == $user)) | length > 0)
  | [.repository.nameWithOwner, (.number|tostring), .title]
  | @tsv')

# 2) My PRs with unresolved comments
MY_PRS_DATA=$(gh api graphql -f query="
{
  search(query: \"is:pr is:open author:${USERNAME} created:>=${START_DATE}\", type: ISSUE, first: 100) {
    nodes {
      ... on PullRequest {
        number
        title
        repository { nameWithOwner }
        reviewThreads(first: 100) {
          nodes { isResolved }
        }
      }
    }
  }
}")

while IFS=$'\t' read -r repo number title; do
  [[ -z "$number" ]] && continue
  add_result "$repo" "$number" "$title" "unresolved comments on my PR"
done < <(echo "$MY_PRS_DATA" | jq -r '
  .data.search.nodes[]
  | select(.reviewThreads.nodes | map(select(.isResolved == false)) | length > 0)
  | [.repository.nameWithOwner, (.number|tostring), .title]
  | @tsv')

# 3) Mentioned in PRs - check for unresolved threads mentioning me
MENTION_PRS=$(gh search prs --mentions "$USERNAME" --created ">=${START_DATE}" --state open --limit 100 --json repository,number,title 2>/dev/null || echo '[]')

while IFS=$'\t' read -r full_name number title; do
  [[ -z "$number" ]] && continue
  # Skip if already seen
  grep -qxF "${full_name}#${number}" "$SEEN" 2>/dev/null && continue

  OWNER="${full_name%/*}"
  REPO="${full_name#*/}"

  THREAD_DATA=$(gh api graphql -f query="
  {
    repository(owner: \"${OWNER}\", name: \"${REPO}\") {
      pullRequest(number: ${number}) {
        reviewThreads(first: 100) {
          nodes {
            isResolved
            comments(first: 5) {
              nodes { body }
            }
          }
        }
      }
    }
  }")

  HAS_MENTION=$(echo "$THREAD_DATA" | jq -r --arg user "$USERNAME" '
    [.data.repository.pullRequest.reviewThreads.nodes[]
    | select(.isResolved == false)
    | select(.comments.nodes[].body | test("@" + $user))]
    | if length > 0 then "yes" else "no" end')

  if [[ "$HAS_MENTION" == "yes" ]]; then
    add_result "$full_name" "$number" "$title" "mentioned in unresolved comment"
  fi
done < <(echo "$MENTION_PRS" | jq -r '.[] | [.repository.nameWithOwner, (.number|tostring), .title] | @tsv')

# --- Output ---
COUNT=$(wc -l < "$RESULTS" | tr -d ' ')
if [[ "$COUNT" -eq 0 ]]; then
  echo "No PRs require your personal attention (since ${START_DATE})."
  exit 0
fi

printf "| %-35s | %5s | %-60s | %-30s |\n" "Repo" "PR #" "Title" "Reason"
printf "|%s|%s|%s|%s|\n" "$(printf '%0.s-' $(seq 1 37))" "$(printf '%0.s-' $(seq 1 7))" "$(printf '%0.s-' $(seq 1 62))" "$(printf '%0.s-' $(seq 1 32))"

while IFS='|' read -r repo number title reason; do
  [[ ${#title} -gt 58 ]] && title="${title:0:55}..."
  printf "| %-35s | %5s | %-60s | %-30s |\n" "$repo" "$number" "$title" "$reason"
done < "$RESULTS"

echo ""
echo "${COUNT} PR(s) need your attention."
