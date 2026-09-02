# ryvx-sandbox

The container image Ryvx runs scan agents inside.

```
docker pull ghcr.io/harryc295/ryvx-sandbox:latest
```

About 1.75 GB.

## What this is

Ryvx runs each agent's shell commands in its own container. Without this
image that container is a bare Python interpreter, so an agent told to
reach for `nmap` or `sqlmap` finds nothing there. Scans still run, they
just have far less to work with.

The image is `debian:bookworm-slim` plus the toolchain:

`nmap`, `masscan`, `subfinder`, `httpx`, `ffuf`, `gobuster`, `nikto`,
`dirb`, `nuclei`, `sqlmap`, `whatweb`, `bandit`, `semgrep`, `trufflehog`,
`gitleaks`, `hydra`, `curl`

## What this is not

**It contains no Ryvx source code.** The only `COPY` in the Dockerfile is
`requirements-sandbox.txt`. CI asserts this on every publish: it searches
the built image for any `ryvx` Python file and fails the build if one is
found.

That is the reason this repository exists separately. A GHCR package
inherits the visibility of the repo that pushes it, so building this from
the private Ryvx repo produced a private package no CLI user could pull,
and making that package public would have tied image visibility to a
private codebase. Owning the Dockerfile here means the image is public
because this repo is public, and the private repo is not involved.

## Using it

Ryvx finds it automatically once it is present locally:

```
ryvx setup          # reports whether the image is present
ryvx setup --fix    # pulls it for you
```

Nothing is ever pulled implicitly during a scan. The image is optional:
Ryvx does not fail without it and `ryvx setup` does not exit non-zero
just because you have not downloaded it.

Building it yourself works too, and needs no access to anything private:

```
docker build -t ryvx-sandbox -f Dockerfile .
```

## Ryvx

Install: <https://ryvx.dev/docs/install/>
