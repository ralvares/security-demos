
# Policies Overview

This directory contains example security policies for demonstration purposes.

## log4shell Policy

The `log4shell` policy is designed to identify known CVEs (Common Vulnerabilities and Exposures) in your workloads. For example, it can detect the presence of the Log4Shell vulnerability (CVE-2021-44228) in container images or application dependencies. This policy relies on vulnerability scanners to find and flag CVEs, helping you quickly identify and mitigate critical security issues.

## httpd-server-version Policy

The `httpd-server-version` policy focuses on identifying risky components in your environment, even if a vulnerability scanner does not explicitly find a CVE. For example, it can detect the use of outdated or unsupported versions of the Apache HTTP server. By flagging the presence of such components, this policy helps you proactively manage risk, even when specific CVEs are not yet known or detected by scanners.

---

**Summary:**
- The `log4shell` policy identifies workloads with known CVEs.
- The `httpd-server-version` policy identifies risky components, providing defense-in-depth even when CVEs are not detected.
