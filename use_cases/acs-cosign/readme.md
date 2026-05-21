# Image Signature Verification with Cosign

This demo shows how ACS enforces image signature policies using Red Hat's Cosign signing keys. Unsigned images are blocked at deploy time; signed images pass through.

---

## Policy Configuration

Create (or enable) the following policy in ACS, scoped to the `payments-v2` namespace:

| Field       | Value |
|-------------|-------|
| **Name**        | Images must be signed by a release key |
| **Scope**       | `payments-v2` namespace |
| **Category**    | Supply Chain |
| **Description** | Alert when images are not digitally signed by Red Hat |
| **Rationale**   | Images should be signed using Red Hat's Cosign product signing keys ([https://access.redhat.com/security/team/key](https://access.redhat.com/security/team/key)) |
| **Guidance**    | Confirm the authenticity of the image by reaching out to Red Hat support |

---

## Demo Steps

### 1. Deploy an Unsigned Image (Blocked)

Deploy an Alpine container — this image is not signed by Red Hat's key and should be blocked by the policy:

```bash
oc run alpine-sleep -n payments-v2 --image=alpine:latest --as=alice --command -- tail -f /dev/null
```

### 2. Deploy a Signed Image (Allowed)

Deploy a UBI container — this image is signed by Red Hat and should be admitted:

```bash
oc run ubi-sleep -n payments-v2 --image=registry.access.redhat.com/ubi9/ubi:latest --as=alice --command -- sleep infinity
```

---
