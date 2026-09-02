# Optional, opt-in sandbox image with a real security-tool arsenal installed
# — the thing that makes ryvx/prompts.py's TOOL_CATALOG stop being
# aspirational. The default image (python:3.12-slim, see sandbox.py) stays
# small and fast for the common case of reviewing your own source; build
# this one when you want agents to actually be able to run nmap/sqlmap/
# semgrep/nuclei/etc via run_shell.
#
# Build:   docker build -t ryvx-sandbox -f containers/Dockerfile .
# Use it:  export RYVX_SANDBOX_IMAGE=ryvx-sandbox
#
# Base: debian:bookworm-slim (Debian stable), not a rolling/testing distro —
# see docs/superpowers/specs/2026-07-27-sandbox-minimal-base-design.md for
# why (this project already got burned once by a rolling curated distro's
# version drift, on the RE-sandbox image). Every tool here is a headless CLI
# binary, so none of Kali's actual differentiators (desktop env, curated
# interactive workflows) were ever in play.

FROM debian:bookworm-slim

# Packaged in Debian bookworm's own apt repo — no pinning needed beyond
# whatever bookworm ships, since bookworm itself is a fixed stable release.
RUN apt-get update && apt-get install -y --no-install-recommends \
        nmap masscan whatweb gobuster ffuf dirb \
        sqlmap hydra \
        perl libjson-perl libxml-writer-perl git curl unzip ca-certificates \
        python3 python3-pip jq \
    && rm -rf /var/lib/apt/lists/*

# Pure-Perl, not packaged in bookworm — pinned tag, no build step needed.
RUN git clone --branch 2.6.0 --depth 1 https://github.com/sullo/nikto /opt/nikto \
    && ln -s /opt/nikto/program/nikto.pl /usr/local/bin/nikto \
    && chmod +x /opt/nikto/program/nikto.pl

# Static/code analysis — not reliably packaged in apt, pip is the stable path.
# Must run *before* the pinned-binary install below: semgrep's dependency
# chain pulls in the Python `httpx` package, which installs its own
# console-script at /usr/local/bin/httpx — if pip ran last it would silently
# clobber ProjectDiscovery's httpx binary.
#
# D-2 (2026-08-09): --require-hashes against a real, pip-compiled lockfile
# instead of an unpinned `pip3 install semgrep bandit` -- a compromised or
# typosquatted release of any of semgrep/bandit's own transitive deps used
# to be able to silently land in every future sandbox image build.
# requirements-sandbox.txt is generated (not hand-edited) via:
#   pip-compile --generate-hashes --output-file=requirements-sandbox.txt containers/requirements-sandbox.in
# run inside a matching debian:bookworm-slim/python3 container -- resolving
# on a different Python version can silently pick incompatible pins.
COPY requirements-sandbox.txt /tmp/requirements-sandbox.txt
RUN pip3 install --no-cache-dir --break-system-packages --require-hashes -r /tmp/requirements-sandbox.txt \
    && rm /tmp/requirements-sandbox.txt

# Not packaged in bookworm at all — pinned GitHub release binaries, no Go
# toolchain needed in the final image.
RUN set -eux; \
    curl -fsSL -o /tmp/nuclei.zip https://github.com/projectdiscovery/nuclei/releases/download/v3.11.0/nuclei_3.11.0_linux_amd64.zip \
    && unzip -qo /tmp/nuclei.zip -d /usr/local/bin nuclei && rm /tmp/nuclei.zip \
    && curl -fsSL -o /tmp/subfinder.zip https://github.com/projectdiscovery/subfinder/releases/download/v2.14.0/subfinder_2.14.0_linux_amd64.zip \
    && unzip -qo /tmp/subfinder.zip -d /usr/local/bin subfinder && rm /tmp/subfinder.zip \
    && curl -fsSL -o /tmp/httpx.zip https://github.com/projectdiscovery/httpx/releases/download/v1.10.0/httpx_1.10.0_linux_amd64.zip \
    && unzip -qo /tmp/httpx.zip -d /usr/local/bin httpx && rm /tmp/httpx.zip \
    && curl -fsSL -o /tmp/gitleaks.tar.gz https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz \
    && tar -xzf /tmp/gitleaks.tar.gz -C /usr/local/bin gitleaks && rm /tmp/gitleaks.tar.gz \
    && curl -fsSL -o /tmp/trufflehog.tar.gz https://github.com/trufflesecurity/trufflehog/releases/download/v3.96.0/trufflehog_3.96.0_linux_amd64.tar.gz \
    && tar -xzf /tmp/trufflehog.tar.gz -C /usr/local/bin trufflehog && rm /tmp/trufflehog.tar.gz \
    && chmod +x /usr/local/bin/nuclei /usr/local/bin/subfinder /usr/local/bin/httpx /usr/local/bin/gitleaks /usr/local/bin/trufflehog

# Keep nuclei's template DB current at build time (agents can re-run
# `nuclei -update-templates` themselves for a fresher set at scan time)
RUN nuclei -update-templates || true

WORKDIR /workspace
CMD ["sleep", "infinity"]
