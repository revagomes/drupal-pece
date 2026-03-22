# Kubernetes Manifest Validation

This directory contains scripts for validating Kubernetes manifests.

## Scripts

### validate-k8s.sh (Recommended)

Wrapper script that automatically handles dependencies and runs validation.

**Usage:**
```bash
# Validate default directory (deploy/kubernetes/)
bash scripts/validate-k8s.sh

# Validate specific directory
bash scripts/validate-k8s.sh /path/to/manifests
```

**Features:**
- Automatically checks for and installs PyYAML if needed
- Sets up proper Python path
- User-friendly colored output

### validate-k8s-manifests.py

Python script that performs the actual validation.

**Usage:**
```bash
python3 scripts/validate-k8s-manifests.py [directory]
```

**Validation Checks:**
- ✅ YAML syntax validation
- ✅ Required Kubernetes fields (apiVersion, kind, metadata)
- ✅ Resource-specific field requirements
- ✅ Container specifications for workload resources
- ✅ Metadata name requirements
- ✅ Namespace requirements for namespaced resources

**Supported Resources:**
- Namespace, ConfigMap, Secret
- Service, Ingress
- Deployment, StatefulSet, DaemonSet
- Job, CronJob
- PersistentVolume, PersistentVolumeClaim
- HorizontalPodAutoscaler
- And more...

## Requirements

- Python 3.6+
- PyYAML (automatically installed by wrapper script)

## CI/CD Integration

This validation can be integrated into CI/CD pipelines:

```yaml
# GitHub Actions example
- name: Validate Kubernetes Manifests
  run: bash scripts/validate-k8s.sh
```

```bash
# GitLab CI example
validate-k8s:
  script:
    - bash scripts/validate-k8s.sh
```

## Exit Codes

- `0`: All manifests are valid
- `1`: Validation failed or error occurred
