---
title: Bring your own image
date: 2026-05-18
---

Two reasons you'd swap the image:

1. **Pin a specific Publisher build** for production change control.
2. **Mirror to your own registry** for air-gapped or proxy-only egress.

## Pin a specific tag

```yaml
image:
  repository: netskopeprivateaccess/publisher_u22
  tag: "100.0.0.1234"   # exact build from Netskope's release notes
  pullPolicy: IfNotPresent
```

`helm upgrade` triggers a rolling restart with the new tag.

## Mirror to a private registry

1. **Pull and re-push** the Publisher image:

   ```bash
   docker pull netskopeprivateaccess/publisher_u22:100.0.0.1234
   docker tag netskopeprivateaccess/publisher_u22:100.0.0.1234 \
     registry.internal.example/npa/publisher_u22:100.0.0.1234
   docker push registry.internal.example/npa/publisher_u22:100.0.0.1234
   ```

2. **Configure pull credentials** as a Kubernetes secret:

   ```bash
   kubectl create secret docker-registry npa-pull \
     --namespace npa-publisher \
     --docker-server=registry.internal.example \
     --docker-username=... \
     --docker-password=...
   ```

3. **Reference both in your values:**

   ```yaml
   image:
     repository: registry.internal.example/npa/publisher_u22
     tag: "100.0.0.1234"
   imagePullSecrets:
     - name: npa-pull
   ```

## Verifying the build

```bash
kubectl exec -n npa-publisher \
  $(kubectl get pod -n npa-publisher -l app.kubernetes.io/name=kubernetes-netskope-publisher -o jsonpath='{.items[0].metadata.name}') \
  -c publisher -- /usr/local/bin/npa_publisher --version
```

Compare against the version field in the Netskope console for the
enrolled Publisher.
