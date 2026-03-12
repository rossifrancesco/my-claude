---
name: my-prs
description: List PRs requiring my attention - where I'm personally requested as reviewer (not via team) or mentioned in unresolved comments. Excludes merged PRs.
allowed-tools: Bash
---

# My PRs - Review Requests & Mentions

Find open PRs that need my personal attention.

## Arguments

`$ARGUMENTS` can specify a custom time range (e.g. `/my-prs 2 weeks`, `/my-prs 3 days`, `/my-prs 1 month`).
If no argument is provided, default to **1 week**.

## Steps

1. Get the GitHub username:
   ```bash
   gh api user --jq '.login'
   ```

2. Use GraphQL to search for PRs where I'm requested as reviewer, filtering to **only direct personal requests** (not team-based):
   ```bash
   gh api graphql -f query='
   {
     search(query: "is:pr is:open review-requested:<USERNAME> created:>=<ONE_WEEK_AGO>", type: ISSUE, first: 100) {
       nodes {
         ... on PullRequest {
           number
           title
           url
           repository { nameWithOwner }
           createdAt
           reviewRequests(first: 20) {
             nodes {
               requestedReviewer {
                 ... on User { login }
                 ... on Team { name slug }
               }
             }
           }
         }
       }
     }
   }'
   ```
   Filter the results: only include PRs where `requestedReviewer.login` matches the username exactly. Exclude any PR where the request comes only through a team.

3. Search for open PRs where I'm mentioned (last week, not merged):
   ```bash
   gh search prs --mentions <USERNAME> --created ">=<ONE_WEEK_AGO>" --state open --limit 100
   ```

4. For any PRs found via mentions, check for **unresolved** review threads mentioning the user using GraphQL:
   ```bash
   gh api graphql -f query='
   {
     repository(owner: "<OWNER>", name: "<REPO>") {
       pullRequest(number: <NUMBER>) {
         reviewThreads(first: 100) {
           nodes {
             isResolved
             comments(first: 5) {
               nodes { author { login } body }
             }
           }
         }
       }
     }
   }'
   ```
   Only include PRs that have at least one **unresolved** thread where the user's `@username` appears in a comment body.

5. Present results as a table with columns: Repo, PR #, Title, Reason (personal review request / mentioned in unresolved comment).

## Date Calculation

`<START_DATE>` = today's date minus the requested time range, in `YYYY-MM-DD` format. Default: 7 days ago.

Replace all occurrences of `<ONE_WEEK_AGO>` in the queries above with `<START_DATE>`.

## Output

- If no PRs found, say "No PRs require your personal attention."
- If PRs found, show a markdown table and a short summary.
