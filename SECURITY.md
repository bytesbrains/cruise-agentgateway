# Security

## What is in scope

This repository publishes **configuration and a smoke test**. It runs no service, ships no image and
publishes no package. So the vulnerabilities that matter here are ones in the *recipe* — for example
a configuration that would expose a Cruise key, weaken TLS to the upstream, or cause a key to be
committed or logged by anyone following the README.

Please report those here.

## What is not in scope

- **The Cruise service itself** (`cruise.bytesbrains.net`, `cruise-demo.bytesbrains.net`). Report
  those to BytesBrains directly at `contact@bytesbrains.com`, not through this repository.
- **agentgateway.** It is an upstream project and has its own
  [security policy](https://github.com/agentgateway/agentgateway/blob/main/SECURITY.md).

## How to report

Use **GitHub's private vulnerability reporting** on this repository — the *Security* tab, *Report a
vulnerability*. That keeps the report private until there is a fix.

If that is unavailable to you, email `contact@bytesbrains.com` with `cruise-agentgateway` in the
subject. Please do not open a public issue for something exploitable.

We do not publish a response-time commitment for this repository, and would rather say so than
promise one we have not staffed.

## If you have leaked a key

A `cru_` key in a commit, a log or a screenshot should be rotated rather than deleted — git history
and anything that scraped it will outlive the deletion. Rotate it in your Cruise dashboard first,
then clean up.
