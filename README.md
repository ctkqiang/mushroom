# Mushroom

> A black-box pentest framework, written in Ruby, that simulates AWS
> CloudFormation / IAM privilege-escalation campaigns in order to audit a
> KQL/SIEM detection rule and produce a machine-readable verdict feed showing
> exactly which attack techniques the rule misses.

[![Tests](https://img.shields.io/badge/tests-81%20passing-brightgreen)](#running-tests)
[![RuboCop](https://img.shields.io/badge/rubocop-no%20offenses-brightgreen)](#style)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.2-red)](#prerequisites)
[![License](https://img.shields.io/badge/license-MIT-blue)](#license)

---

## Table of contents

1. [Why this project exists](#why-this-project-exists)
2. [Prerequisites](#prerequisites)
3. [Quick start](#quick-start)
4. [CLI reference](#cli-reference)
5. [Kill chain](#kill-chain)
6. [The five exploit strategies](#the-five-exploit-strategies)
7. [The KQL rule under audit](#the-kql-rule-under-audit)
8. [Verdict feed](#verdict-feed)
9. [Success metric / health check](#success-metric--health-check)
10. [Configuration](#configuration)
11. [Repo layout](#repo-layout)
12. [Architecture](#architecture)
13. [Non-negotiable invariants](#non-negotiable-invariants)
14. [Running tests](#running-tests)
15. [Style](#style)
16. [Adding a new evasion strategy](#adding-a-new-evasion-strategy)
17. [Out of scope](#out-of-scope)
18. [Glossary](#glossary)
19. [License](#license)

---

## Why this project exists

A defender has a KQL rule (Microsoft Sentinel / Azure Log Analytics) that is
supposed to catch CloudFormation-mediated IAM privilege escalation.  The rule
works by:

1. Finding CloudFormation `CreateStack` or `UpdateStack` events in CloudTrail.
2. Inner-joining those events with IAM `CreateRole`, `AttachRolePolicy`, or
   `PutRolePolicy` events **on the same `UserIdentityArn`** within a **1-hour**
   lookback.

That rule contains at least five independently exploitable assumptions.
**Mushroom exists to prove it** — concretely, reproducibly, and without
requiring any manual CloudTrail inspection.

For each assumption, Mushroom:

- Simulates the exact evasion technique that defeats it.
- Records whether the rule would have fired.
- Writes a machine-readable `Verdict` to a JSONL file.

The defender then reads that file, identifies every `original_rule_would_fire: false`
line, and hardens the KQL rule until the count reaches zero.

> Mushroom is **not** a general-purpose exploitation framework.  It is a
> detection regression suite for CloudFormation privilege escalation.  The
> only things it ever creates in AWS are temporary, tagged, sandboxed
> resources — and it cleans them up automatically.

---

## Prerequisites

| Requirement | Version |
|---|---|
| Ruby | ≥ 3.2 |
| Bundler | ≥ 2.4 |
| AWS CLI profile (live mode only) | configured with appropriate IAM permissions |
| `jq` (for the health-check one-liner) | any recent version |

Install Ruby dependencies:

```bash
bundle install
```

---

## Quick start

```bash
# Dry-run — completely safe, no AWS calls, no credentials needed
bundle exec bin/mushroom campaign --target acme-corp
```

Output:

```
[INFO] s3_enum: complete
[INFO] account_id_prober: dry_run — skipping network probe
[INFO] recon: phase complete
[INFO] imds_stealer: dry_run mock credentials
[INFO] harvest: phase complete
[INFO] identity_mapper: dry_run identity
[INFO] discovery: phase complete
[INFO] exploit: begin
[INFO] exploit: service_role_attribution simulated
[INFO] exploit: begin
[INFO] exploit: cloud_control_api simulated
... (5 strategies)

=== Mushroom Campaign Report ===
Campaign ID : mushroom-bce0e58b
Target      : acme-corp
Total       : 5
Bypassed    : 5
Detected    : 0

Verdicts written to: tmp/mushroom-verdicts.jsonl
Audit log written to: tmp/mushroom-audit.jsonl
```

### Live mode (real AWS — sandbox accounts only)

Live mode requires a sandbox account.  Read the
[invariants](#non-negotiable-invariants) section first.

```bash
bundle exec bin/mushroom campaign \
  --target acme-corp \
  --live \
  --ssrf-endpoint https://vulnerable.example.com/proxy \
  --template-bucket my-cfn-templates \
  --execution-role-arn arn:aws:iam::123456789012:role/MyCFNExecutionRole \
  --allow-account 123456789012
```

---

## CLI reference

```
mushroom campaign [options]
```

| Flag | Type | Default | Description |
|---|---|---|---|
| `--target TARGET` | string | **required** | Human-readable target alias (used in campaign ID and logging) |
| `--live` | boolean | `false` | Disable dry-run; make real AWS API calls |
| `--ssrf-endpoint URL` | string | `nil` | SSRF endpoint URL for Phase 2 IMDS harvesting |
| `--template-bucket BUCKET` | string | `nil` | S3 bucket for CloudFormation templates (live mode) |
| `--execution-role-arn ARN` | string | `nil` | CFN service-execution role ARN (required by `ServiceRole` and `IdentitySwitch` in live mode) |
| `--allow-account ID` | string (repeatable) | `[]` | Permit running against this account ID; repeat for multiple |
| `--deny-account ID` | string (repeatable) | `[]` | Hard-block this account ID; repeat for multiple |
| `-c`, `--config FILE` | string | `nil` | Path to a YAML settings file (see `config/settings.example.yml`) |
| `--verdict-path PATH` | string | `tmp/mushroom-verdicts.jsonl` | Override verdict output path |
| `--audit-path PATH` | string | `tmp/mushroom-audit.jsonl` | Override audit log path |
| `-v`, `--version` | — | — | Print version and exit |
| `-h`, `--help` | — | — | Print help and exit |

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Campaign completed (check health-check separately) |
| `1` | Unknown command or missing `--target` |

---

## Kill chain

Mushroom runs four phases in strict order.  Each phase follows the
template-method pattern: `preflight! → execute → run_cleanups`.
Cleanups run in **LIFO order in an `ensure` clause**, so they fire even when
`execute` raises.

```
┌──────────────────────┐
│   Phase 1 · Recon    │  Unauthenticated S3 bucket enumeration,
│                      │  account-ID probing via S3 error oracle,
│                      │  IAM principal brute-forcing via STS error oracle.
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│  Phase 2 · Harvest   │  SSRF → EC2 IMDS credential theft.
│                      │  Builds a Mushroom::Credentials value object.
│                      │  In dry_run: mock credentials are returned.
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Phase 3 · Discovery  │  sts:GetCallerIdentity (whoami).
│                      │  iam:SimulatePrincipalPolicy to enumerate
│                      │  effective permissions without mutations.
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│  Phase 4 · Exploit   │  Runs all five evasion strategies in sequence.
│                      │  Each strategy emits exactly one Verdict.
└──────────────────────┘
```

### Phase 1 — Recon

Three unauthenticated sub-techniques:

| Class | Technique |
|---|---|
| `Recon::S3Enumerator` | Anonymous `HeadBucket` against wordlist-generated names |
| `Recon::AccountIdProber` | S3 access-denied error messages embed the account ID in the ARN |
| `Recon::PrincipalBruteforcer` | STS `AssumeRole` error oracle: `AccessDenied` = principal exists |

All three are no-ops in `dry_run` mode.

### Phase 2 — Harvest

| Class | Technique |
|---|---|
| `Harvest::SsrfClient` | Drives an SSRF endpoint to proxy requests to `169.254.169.254` |
| `Harvest::ImdseStealer` | Parses the IMDS JSON credential blob into a `Mushroom::Credentials` |

In `dry_run` mode, `ImdseStealer` returns hardcoded mock credentials
(`ASIADRYRUNFAKE0001`) and never contacts the SSRF endpoint.

### Phase 3 — Discovery

| Class | Technique |
|---|---|
| `Discovery::IdentityMapper` | `sts:GetCallerIdentity` to establish the caller ARN |
| `Discovery::PermissionFuzzer` | `iam:SimulatePrincipalPolicy` against six CloudFormation/IAM actions |

In `dry_run` mode, `IdentityMapper` returns a mock ARN and sets
`context.account_id = "000000000000"`.  `PermissionFuzzer` returns `"allowed"`
for every probed action.

### Phase 4 — Exploit

Runs `Phases::Exploit::STRATEGIES` in order.  Each strategy is instantiated
fresh with its own cleanup stack.  An `ExploitFailed` exception from one
strategy is logged but does not abort the others.

---

## The five exploit strategies

Each strategy is a subclass of `Exploit::Strategy` and:

- Implements `#scenario_id` → unique string.
- Implements `#simulate` → returns a `Verdict`.
- Gates all AWS mutations behind `config.dry_run?`.
- Registers cleanup blocks with `with_cleanup { ... }`.

| Strategy class | Scenario ID | Assumption broken | Detection gap |
|---|---|---|---|
| `Exploit::ServiceRole` | `service_role_attribution` | `UserIdentityArn` join | CFN uses a service-execution role (`roleARN` parameter). IAM events are emitted by `cloudformation.amazonaws.com`, **not** the human caller. The join on `UserIdentityArn` never matches. |
| `Exploit::CloudControl` | `cloud_control_api` | `EventSource` filter | Cloud Control API provisioning emits events under `cloudcontrolapi.amazonaws.com`. The rule's `EventSource == "cloudformation.amazonaws.com"` filter excludes all Cloud Control traffic. |
| `Exploit::AltIamActions` | `alt_iam_actions` | `EventName` list | `iam:CreatePolicy`, `iam:PutUserPolicy`, `iam:AddUserToGroup`, `iam:AttachGroupPolicy` achieve equivalent privilege escalation but are absent from the monitored `EventName` list. |
| `Exploit::IdentitySwitch` | `identity_switch` | `UserIdentityArn` join (split actors) | Actor A (`CreateStack`) and Actor B (assumed-role IAM mutations) have different `UserIdentityArn` values. The inner join finds zero matching rows. |
| `Exploit::TimeDelay` | `time_delay` | `ago(1h)` window | CFN `CreateStack` and IAM mutations are staged ≥ 2 hours apart. They never co-appear within the `ago(1h)` temporal window the rule queries. |

### Strategy: `ServiceRole` — SANDBOX ONLY

> **Do not run `--live` for this strategy outside a dedicated sandbox account.**
> It provisions a real IAM role via a CloudFormation stack with a
> service-execution role.

In live mode it calls `cfn:CreateStack` with a `roleARN` parameter.  The
stack creates an `AWS::IAM::Role` resource.  The IAM mutations are performed
by `cloudformation.amazonaws.com`, not by the human caller — so the
`UserIdentityArn` join in the rule returns no rows.

Cleanup: `cfn:DeleteStack` is registered in `with_cleanup { ... }` immediately
after `create_stack` succeeds.

### Strategy: `CloudControl`

Calls `cloudcontrolapi:CreateResource` for `AWS::IAM::Role`.  CloudTrail
records this under `EventSource: cloudcontrolapi.amazonaws.com`.  The rule's
`where EventSource == "cloudformation.amazonaws.com"` clause excludes it
entirely.

Cleanup: `cloudcontrolapi:CancelResourceRequest` with the returned request
token.

### Strategy: `AltIamActions`

In live mode calls `iam:CreatePolicy` (not `CreateRole`, `AttachRolePolicy`,
or `PutRolePolicy`).  The policy grants `sts:AssumeRole` — equivalent
privilege escalation path — but the CloudTrail `EventName` is `CreatePolicy`,
which is absent from the rule's filter list.

Cleanup: `iam:DeletePolicy`.

### Strategy: `IdentitySwitch`

In live mode performs `sts:AssumeRole` to switch to a second identity (Actor B),
then simulates IAM mutations under that identity.  The `UserIdentityArn` of
the CFN event (Actor A) and the IAM events (Actor B) differ, so the rule's
inner join returns zero rows.

Requires `--execution-role-arn` in live mode.

### Strategy: `TimeDelay`

Pure simulation — no AWS calls even in live mode.  Calculates two timestamps
that are `SIM_DELAY_HOURS = 2` hours apart (beyond the `ago(1h)` window) and
embeds them in the verdict reason.  Demonstrates that the rule's fixed temporal
boundary is exploitable by pacing the attack.

---

## The KQL rule under audit

```kql
let Timeframe = 1h;
AWSCloudTrail
| where TimeGenerated > ago(Timeframe)
| where EventSource == "cloudformation.amazonaws.com"
| where EventName in ("CreateStack", "UpdateStack")
| extend StackName   = tostring(parse_json(RequestParameters).stackName)
| extend TemplateURL = tostring(parse_json(RequestParameters).templateURL)
| extend RoleARN     = tostring(parse_json(RequestParameters).roleARN)
| project TimeGenerated, UserIdentityArn, EventName, StackName,
          TemplateURL, RoleARN, SourceIpAddress
| join kind=inner (
    AWSCloudTrail
    | where TimeGenerated > ago(Timeframe)
    | where EventSource == "iam.amazonaws.com"
    | where EventName in ("CreateRole", "AttachRolePolicy", "PutRolePolicy")
    | extend CreatedRoleName = tostring(parse_json(RequestParameters).roleName)
) on $left.UserIdentityArn == $right.UserIdentityArn
| project TimeGenerated, UserIdentityArn, SourceIpAddress,
          StackName, TemplateURL, EventName1, CreatedRoleName
```

Mushroom does **not** modify, import, or embed a "hardened" version of this
rule.  The rule lives in the defender's Sentinel workspace.  Mushroom only
produces the verdict feed they consume to guide rule improvements.

### The five fragile assumptions (mapping to strategies)

| Rule clause | Assumption | Strategy that defeats it |
|---|---|---|
| `$left.UserIdentityArn == $right.UserIdentityArn` | CFN and IAM events share the same actor ARN | `ServiceRole`, `IdentitySwitch` |
| `EventSource == "cloudformation.amazonaws.com"` | All CFN-driven provisioning uses CFN's EventSource | `CloudControl` |
| `EventName in ("CreateRole", "AttachRolePolicy", "PutRolePolicy")` | These three are the only IAM escalation actions | `AltIamActions` |
| `TimeGenerated > ago(1h)` … both sides | CFN and IAM actions occur within the same 1-hour window | `TimeDelay` |

---

## Verdict feed

After every run, `tmp/mushroom-verdicts.jsonl` is appended with one JSON line
per strategy.  The file is append-only; re-running appends new lines rather
than overwriting.

### Schema

| Field | Type | Description |
|---|---|---|
| `scenario` | `string` | Unique scenario identifier (e.g. `"cloud_control_api"`) |
| `outcome` | `string` | `"simulated"` \| `"skipped"` \| `"error"` |
| `original_rule_would_fire` | `boolean` | `false` = the rule missed this technique (detection gap) |
| `reason` | `string` | Human-readable explanation of the detection gap |
| `at` | `string` | ISO 8601 timestamp with microsecond precision |

### Example output

```jsonc
{"scenario":"service_role_attribution","outcome":"simulated","original_rule_would_fire":false,"reason":"CFN service role causes IAM events to emit under the CFN service principal ARN, not the human caller ARN — UserIdentityArn join misses the correlation.","at":"2026-10-29T03:33:40.969018Z"}
{"scenario":"cloud_control_api","outcome":"simulated","original_rule_would_fire":false,"reason":"Cloud Control API emits events under cloudcontrolapi.amazonaws.com, not cloudformation.amazonaws.com — EventSource filter excludes it.","at":"2026-10-29T03:33:40.971204Z"}
{"scenario":"alt_iam_actions","outcome":"simulated","original_rule_would_fire":false,"reason":"Alternative IAM actions (iam:CreatePolicy, iam:PutUserPolicy, iam:AddUserToGroup, iam:AttachGroupPolicy) achieve equivalent privilege escalation without appearing in the monitored EventName list.","at":"2026-10-29T03:33:40.972101Z"}
{"scenario":"identity_switch","outcome":"simulated","original_rule_would_fire":false,"reason":"CFN CreateStack attributed to Actor A (...) and IAM mutations attributed to Actor B (...); UserIdentityArn join misses the split-identity correlation.","at":"2026-10-29T03:33:40.973041Z"}
{"scenario":"time_delay","outcome":"simulated","original_rule_would_fire":false,"reason":"CFN CreateStack was staged at 2026-10-29T01:33:40Z and IAM mutations at 2026-10-29T03:33:40Z — a 2-hour gap exceeds the ago(1h) rule window; the join finds no overlapping events.","at":"2026-10-29T03:33:40.974010Z"}
```

### Audit log

`tmp/mushroom-audit.jsonl` is a separate append-only JSONL stream containing
every log entry emitted during the run, including phase lifecycle events,
strategy milestones, and cleanup results.  It is written by `Mushroom::Logger`
and is suitable for post-hoc forensic review.

---

## Success metric / health check

```bash
jq -s 'map(select(.original_rule_would_fire == false)) | length' \
    tmp/mushroom-verdicts.jsonl
# must return 0 before the project is considered complete
```

The health check counts open detection gaps.  Currently returns **5** (baseline
rule misses all five techniques).  Every `false` must be resolved by improving
the KQL rule — **not** by removing or disabling the scenario.

### Hardening guidance per scenario

| Scenario | Suggested rule improvement |
|---|---|
| `service_role_attribution` | Correlate `RoleARN` in CFN `RequestParameters` with the `roleName` in IAM events, rather than joining on `UserIdentityArn`. |
| `cloud_control_api` | Add `EventSource in ("cloudformation.amazonaws.com", "cloudcontrolapi.amazonaws.com")` to the outer filter. |
| `alt_iam_actions` | Extend the IAM `EventName` filter to include `CreatePolicy`, `PutUserPolicy`, `AddUserToGroup`, `AttachGroupPolicy`. |
| `identity_switch` | Correlate events by stack/role resource name rather than actor ARN alone. Consider a watchlist or multi-step correlation. |
| `time_delay` | Increase `Timeframe` or implement a persistent lookup that survives across multiple 1-hour windows (e.g. a watchlist or external entity table). |

---

## Configuration

All settings can be provided via a YAML file (`-c`) and/or CLI flags.  CLI
flags take precedence over YAML, which takes precedence over built-in defaults.

Copy `config/settings.example.yml` to get started:

```bash
cp config/settings.example.yml config/settings.yml
bundle exec bin/mushroom campaign --target acme -c config/settings.yml
```

### Full settings reference

```yaml
# config/settings.example.yml

# Master dry-run switch.  Set to false only for sandbox live runs.
dry_run: true

# Master cleanup switch.  Keep true unless debugging a failed cleanup.
cleanup: true

# Allowlist: only these account IDs may be targeted.
# Leave empty to allow any account (rely on deny_accounts for safety).
allow_accounts: []
# - "123456789012"

# Denylist: these account IDs are unconditionally blocked.
deny_accounts: []
# - "000000000000"

# Phase 2 SSRF endpoint (live mode only).
# ssrf_endpoint: "https://vulnerable.example.com/proxy"

# S3 bucket for CloudFormation templates (ServiceRole live mode).
# template_bucket: "my-cfn-templates-bucket"

# ARN of the CloudFormation service-execution role (ServiceRole / IdentitySwitch live mode).
# execution_role_arn: "arn:aws:iam::123456789012:role/MyCFNExecutionRole"

# Named AWS CLI/SDK profile to use for API calls.
# profile: "my-sandbox-profile"

# Output paths (relative to working directory).
verdict_path: "tmp/mushroom-verdicts.jsonl"
audit_path:   "tmp/mushroom-audit.jsonl"

# Lookback window in hours — informational only (used in TimeDelay simulation).
timeframe_hours: 1
```

### Environment variables

The AWS SDK respects the standard environment variables
(`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`,
`AWS_DEFAULT_REGION`, `AWS_PROFILE`) as a credential chain fallback, but
Mushroom does not read them directly.  Use `--config` with a `profile:` key or
inject stolen credentials via `context.credentials` for full control.

---

## Repo layout

```
mushroom/
├── bin/
│   └── mushroom                        # Thin shim → Mushroom::CLI.start(ARGV)
│
├── config/
│   ├── settings.example.yml            # Annotated example configuration
│   └── wordlists/
│       ├── buckets.txt                 # S3 bucket name candidates (Recon Phase 1)
│       ├── roles.txt                   # IAM role name candidates (Recon Phase 1)
│       └── users.txt                   # IAM user name candidates (Recon Phase 1)
│
├── lib/
│   ├── mushroom.rb                     # Autoload entry point; stdlib + SDK requires
│   └── mushroom/
│       ├── version.rb                  # VERSION, AUTHOR constants
│       ├── errors.rb                   # Exception tree (all inherit Mushroom::Error)
│       ├── config.rb                   # Frozen Config; YAML merge + assert_safe!
│       ├── logger.rb                   # Dual STDOUT + append-only JSONL sink
│       ├── credentials.rb              # Data.define value object; from_imds, from_sts
│       ├── verdict.rb                  # Data.define value object; bypass?, to_h
│       ├── verdict_store.rb            # Enumerable append-only JSONL sink
│       ├── context.rb                  # Mutable campaign state (only mutable state)
│       ├── aws_clients.rb              # Mixin: lazy CFN/IAM/STS/S3/CC clients
│       ├── phase.rb                    # Template-method base; with_cleanup LIFO
│       ├── campaign.rb                 # Four-phase orchestrator; Enumerable; report
│       ├── cli.rb                      # OptionParser front-end
│       │
│       ├── recon/
│       │   ├── s3_enumerator.rb        # Anonymous HeadBucket wordlist probe
│       │   ├── account_id_prober.rb    # S3 error-oracle account-ID extraction
│       │   └── principal_bruteforcer.rb # STS AssumeRole error-oracle IAM enumeration
│       │
│       ├── harvest/
│       │   ├── ssrf_client.rb          # HTTP client that proxies through SSRF endpoint
│       │   └── imds_stealer.rb         # IMDS JSON parser → Credentials value object
│       │
│       ├── discovery/
│       │   ├── identity_mapper.rb      # sts:GetCallerIdentity (whoami)
│       │   └── permission_fuzzer.rb    # iam:SimulatePrincipalPolicy
│       │
│       ├── exploit/
│       │   ├── strategy.rb             # Abstract base; build_verdict; resource_tags
│       │   ├── service_role.rb         # Evasion: CFN service-execution role (SANDBOX)
│       │   ├── cloud_control.rb        # Evasion: Cloud Control API EventSource
│       │   ├── alt_iam_actions.rb      # Evasion: unlisted IAM EventNames
│       │   ├── identity_switch.rb      # Evasion: two-actor UserIdentityArn split
│       │   └── time_delay.rb           # Evasion: temporal window bypass
│       │
│       └── phases/
│           ├── recon.rb                # Phase 1 orchestrator
│           ├── harvest.rb              # Phase 2 orchestrator
│           ├── discovery.rb            # Phase 3 orchestrator
│           └── exploit.rb              # Phase 4 orchestrator; STRATEGIES constant
│
├── spec/
│   ├── spec_helper.rb
│   └── mushroom/
│       ├── campaign_spec.rb
│       ├── config_spec.rb
│       ├── context_spec.rb
│       ├── credentials_spec.rb
│       ├── errors_spec.rb
│       ├── logger_spec.rb
│       ├── phase_spec.rb
│       ├── verdict_spec.rb
│       ├── verdict_store_spec.rb
│       ├── recon/
│       │   ├── s3_enumerator_spec.rb
│       │   └── account_id_prober_spec.rb
│       ├── harvest/
│       │   └── imds_stealer_spec.rb
│       ├── discovery/
│       │   ├── identity_mapper_spec.rb
│       │   └── permission_fuzzer_spec.rb
│       └── exploit/
│           ├── strategy_spec.rb
│           ├── service_role_spec.rb
│           ├── cloud_control_spec.rb
│           ├── alt_iam_actions_spec.rb
│           ├── identity_switch_spec.rb
│           └── time_delay_spec.rb
│
├── tmp/                                # Runtime output (gitignored)
│   ├── mushroom-verdicts.jsonl         # Machine-readable verdict feed
│   └── mushroom-audit.jsonl            # Full structured audit log
│
├── .rubocop.yml                        # RuboCop configuration
├── Gemfile
├── Gemfile.lock
└── README.md
```

---

## Architecture

### Design patterns

| Pattern | Where used |
|---|---|
| **Template method** | `Phase#call` (preflight → execute → run_cleanups); `Strategy#call` (log → simulate → cleanup) |
| **Strategy** | `Exploit::Strategy` subclasses — each encapsulates one evasion technique |
| **Mixin** | `AwsClients` — included by `Phase` and `Strategy`; provides lazy SDK clients |
| **Immutable value object** | `Credentials`, `Verdict` — built with `Data.define` |
| **Enumerable** | `VerdictStore`, `Campaign` — expose collections via `each` |
| **Single mutable state** | `Context` — the only object that accumulates state across phases |

### Key design decisions

#### `Data.define` for value objects

`Credentials` and `Verdict` use Ruby 3.2's `Data.define` rather than
`Struct` or plain `Hash`.  This gives:

- Immutability by default (frozen after construction).
- Named fields with keyword-argument constructors.
- Pattern-matching support.
- No accidental field omission — every field must be supplied at construction.

#### LIFO cleanup stack

Every phase and strategy maintains a `@cleanups` array.  `with_cleanup { ... }`
appends a block to it.  `run_cleanups` iterates in reverse (`@cleanups.reverse_each`)
inside an `ensure` clause, so cleanup order mirrors creation order in reverse —
exactly like a stack-based destructor.  Individual cleanup failures are logged
as warnings but never propagate.

#### No global state

All mutable state flows through `Mushroom::Context`, which is created once per
campaign and threaded explicitly through phases and strategies.  There are no
class-level instance variables, no module-level globals, and no
`Thread.current` hacks.

#### Dry-run is the default

`Config::DEFAULTS` sets `dry_run: true`.  Every AWS mutation in every
phase/strategy is gated:

```ruby
unless config.dry_run?
  # real AWS call here
end
```

The `--live` CLI flag inverts this.  Forgetting `--live` is always safe.

---

## Non-negotiable invariants

These rules must never be relaxed, regardless of how the project evolves.

### 1. `dry_run: true` is the default

Every AWS write/mutate call **must** be gated behind `config.dry_run?`.
`--live` is required to make real calls.  New strategies must follow the same
pattern — no exceptions.

### 2. `cleanup: true` is the default

Every `create_*` call **must** be immediately followed by a
`with_cleanup { ... }` registration.  `run_cleanups` is called in the `ensure`
clause of `Phase#call` and `Strategy#call`.  Do not skip cleanup for
"temporary" resources.

### 3. Tag every resource

Every AWS resource created must carry the tag:

```
Simulation = <campaign_id>-<scenario_id>
```

Built from `Strategy#resource_tags`.  This enables out-of-band cleanup if
an in-process cleanup fails.

### 4. Account allow/deny lists are always honoured

`Config#assert_safe!(account_id:)` is called in `Phase#preflight!` and
again after `context.account_id` is populated in the Discovery phase.  New
phases and strategies must not bypass this check.

### 5. `ServiceRole` is sandbox-only

`Exploit::ServiceRole` must only be run against dedicated sandbox accounts.
This is documented in the strategy's comment block, in the README (here), and
enforced by the `--execution-role-arn` requirement in live mode.

### 6. No raw credential output

Access keys must never appear in STDOUT, the audit log, or any log field.
Always use `Credentials#redacted`, which masks everything after the four-char
prefix (e.g. `ASIA`) and appends the source ARN for traceability.

---

## Running tests

```bash
bundle exec rspec                              # all specs
bundle exec rspec --format documentation      # verbose output
bundle exec rspec spec/mushroom/config_spec.rb # single file
```

### Test suite structure

| Spec file | Coverage |
|---|---|
| `campaign_spec.rb` | Full five-strategy dry run; account deny preflight |
| `config_spec.rb` | `.load` defaults, YAML merge, overrides, `assert_safe!`, `[]`, `to_h` |
| `context_spec.rb` | Defaults, campaign_id uniqueness, mutation, custom region |
| `credentials_spec.rb` | `from_imds`, `to_aws`, `expired?`, `redacted` |
| `errors_spec.rb` | Full hierarchy, inheritance, message, cross-rescue |
| `logger_spec.rb` | JSONL output, IO output, level filtering, append, double-close, mkdir |
| `phase_spec.rb` | LIFO cleanup order under exception |
| `verdict_spec.rb` | ISO 8601 µs precision, `bypass?`, serialisation |
| `verdict_store_spec.rb` | Append + flush, Enumerable, chaining, count, double-close, mkdir |
| `recon/s3_enumerator_spec.rb` | Dry-run no-op, candidate name generation |
| `recon/account_id_prober_spec.rb` | Dry-run returns nil |
| `harvest/imds_stealer_spec.rb` | Dry-run mock; live error paths (no names, empty, no creds, bad JSON) |
| `discovery/identity_mapper_spec.rb` | Dry-run mock ARN, account_id side-effect |
| `discovery/permission_fuzzer_spec.rb` | Dry-run mock results, custom actions list |
| `exploit/strategy_spec.rb` | Verdict append, LIFO cleanup under raise, resource_tags, NotImplementedError |
| `exploit/service_role_spec.rb` | scenario_id, bypass verdict, reason content, store append |
| `exploit/cloud_control_spec.rb` | scenario_id, bypass verdict, EventSource in reason |
| `exploit/alt_iam_actions_spec.rb` | scenario_id, ALT_PAIRS length, reason content |
| `exploit/identity_switch_spec.rb` | scenario_id, two-actor reason, credentials source_arn |
| `exploit/time_delay_spec.rb` | scenario_id, SIM_DELAY_HOURS > 1h, reason gap, timestamp math |

**Current result: 81 examples, 0 failures.**

---

## Style

```bash
bundle exec rubocop          # check
bundle exec rubocop -a       # auto-correct
bundle exec rubocop -A       # auto-correct (unsafe)
```

**Current result: 37 files inspected, no offenses detected.**

Key style conventions enforced:

- `# frozen_string_literal: true` in every file.
- `Style/ClassAndModuleChildren: nested`.
- Single-quoted strings unless interpolation is required.
- No `method_missing`, no `eval`, no monkey-patching.
- Custom exceptions only — no status-code returns.
- Metrics limits raised in `.rubocop.yml` for phase orchestrators and the CLI
  option parser (inherently verbose by nature).

---

## Adding a new evasion strategy

Follow these steps exactly.  Do not deviate from the structure.

### 1. Create the strategy class

```
lib/mushroom/exploit/my_strategy.rb
```

```ruby
# frozen_string_literal: true

module Mushroom
  module Exploit
    # Strategy: Exploit::MyStrategy
    # Scenario ID: my_scenario_id
    #
    # Evasion technique:
    #   <describe which rule assumption is broken>
    #
    # Detection gap:
    #   <describe how the rule must be hardened>
    class MyStrategy < Strategy
      SCENARIO = 'my_scenario_id'

      def scenario_id = SCENARIO

      protected

      def simulate
        unless config.dry_run?
          # create AWS resources
          with_cleanup { # delete them }
        end

        build_verdict(
          outcome: :simulated,
          original_rule_would_fire: false,
          reason: 'Explain exactly why the rule misses this.'
        )
      end
    end
  end
end
```

### 2. Add a `require_relative` in `lib/mushroom.rb`

```ruby
require_relative 'mushroom/exploit/my_strategy'
```

### 3. Add to `Phases::Exploit::STRATEGIES`

```ruby
# lib/mushroom/phases/exploit.rb
STRATEGIES = [
  Mushroom::Exploit::ServiceRole,
  Mushroom::Exploit::CloudControl,
  Mushroom::Exploit::AltIamActions,
  Mushroom::Exploit::IdentitySwitch,
  Mushroom::Exploit::TimeDelay,
  Mushroom::Exploit::MyStrategy,   # ← add here
].freeze
```

### 4. Add a row to the strategy table in this README

```
| `Exploit::MyStrategy` | `my_scenario_id` | <assumption broken> | <detection gap> |
```

### 5. Write a spec

```
spec/mushroom/exploit/my_strategy_spec.rb
```

At minimum test: `scenario_id`, bypass verdict in dry_run, store append.

### 6. Update the health-check baseline

The expected count in `spec/mushroom/campaign_spec.rb` line
`expect(scenarios).to match_array(...)` must be updated to include
`'my_scenario_id'`, and the bypassed count updated accordingly.

---

## Out of scope

The following will never be part of this project:

- **Other AWS services.** Only CloudFormation, IAM, S3, STS, and Cloud Control.
- **Persistence, lateral movement, data exfiltration.** Mushroom creates
  temporary tagged resources and deletes them.  Nothing more.
- **A GUI, web server, or database.** Mushroom is a CLI tool with a JSONL
  output file.
- **Rewriting or auto-fixing the KQL rule.** The rule lives in the defender's
  Sentinel workspace.  Mushroom only produces the verdict feed they consume.
- **Hardened rule variants inside this repo.** Do not reference or store a
  "fixed" KQL rule here — the whole point is that Mushroom measures the
  baseline rule as-is.
- **Rewriting in another language.** The Ruby idioms (`Data.define`,
  `Enumerable`, mixin strategy pattern) are load-bearing design choices, not
  incidental.

---

## Glossary

| Term | Definition |
|---|---|
| **Verdict** | A `Data.define` record capturing the outcome of one exploit strategy: scenario ID, outcome, whether the rule fired, reason, and timestamp. |
| **VerdictStore** | Append-only `Enumerable` JSONL sink; the single source of truth for campaign results. |
| **Campaign** | The top-level orchestrator that runs all four phases and exposes collected verdicts as `Enumerable`. |
| **Phase** | An abstract template-method class. Subclasses implement `#execute`. |
| **Strategy** | An abstract base for exploit techniques. Subclasses implement `#scenario_id` and `#simulate`. |
| **Context** | The single mutable object threaded through all phases; holds discovered data (account ID, credentials, buckets, principals). |
| **dry_run** | When `true` (the default), all AWS mutations are skipped. Mock data is returned instead. |
| **bypass** | A verdict where `original_rule_would_fire: false` — the KQL rule was evaded. |
| **health check** | `jq -s 'map(select(.original_rule_would_fire == false)) \| length' tmp/mushroom-verdicts.jsonl` — must return `0` for the project to be complete. |
| **IMDS** | EC2 Instance Metadata Service (`169.254.169.254`). Targeted in Phase 2 via SSRF. |
| **SSRF** | Server-Side Request Forgery — a web vulnerability used to proxy requests to IMDS. |
| **CFN** | CloudFormation. |
| **Cloud Control** | AWS Cloud Control API (`cloudcontrolapi.amazonaws.com`) — an alternative provisioning surface that bypasses the CFN EventSource filter. |

---

## License

MIT © [ctkqiang](https://github.com/ctkqiang)
