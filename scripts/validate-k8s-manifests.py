#!/usr/bin/env python3
"""
Kubernetes Manifest Validator
Validates YAML syntax and Kubernetes manifest structure
"""

import sys
import yaml
from pathlib import Path
from typing import List, Dict, Tuple

# Required fields for all Kubernetes resources
REQUIRED_FIELDS = ['apiVersion', 'kind', 'metadata']

# Valid Kubernetes API versions (common ones)
VALID_API_VERSIONS = [
    'v1',
    'apps/v1',
    'batch/v1',
    'batch/v1beta1',
    'autoscaling/v1',
    'autoscaling/v2',
    'networking.k8s.io/v1',
    'policy/v1',
    'rbac.authorization.k8s.io/v1',
    'storage.k8s.io/v1',
]

# Valid Kubernetes kinds
VALID_KINDS = [
    'Namespace', 'ConfigMap', 'Secret', 'Service', 'Deployment',
    'StatefulSet', 'DaemonSet', 'Job', 'CronJob', 'Pod',
    'PersistentVolume', 'PersistentVolumeClaim', 'StorageClass',
    'Ingress', 'NetworkPolicy', 'ServiceAccount', 'Role',
    'RoleBinding', 'ClusterRole', 'ClusterRoleBinding',
    'HorizontalPodAutoscaler', 'PodDisruptionBudget'
]

# Resource-specific validations
RESOURCE_SPECS = {
    'Namespace': ['metadata.name'],
    'ConfigMap': ['metadata.name', 'metadata.namespace'],
    'Secret': ['metadata.name', 'metadata.namespace'],
    'Service': ['metadata.name', 'metadata.namespace', 'spec.selector', 'spec.ports'],
    'Deployment': ['metadata.name', 'metadata.namespace', 'spec.selector', 'spec.template'],
    'StatefulSet': ['metadata.name', 'metadata.namespace', 'spec.selector', 'spec.template', 'spec.serviceName'],
    'PersistentVolumeClaim': ['metadata.name', 'metadata.namespace', 'spec.accessModes', 'spec.resources'],
    'Ingress': ['metadata.name', 'metadata.namespace', 'spec'],
    'HorizontalPodAutoscaler': ['metadata.name', 'metadata.namespace', 'spec.scaleTargetRef', 'spec.minReplicas', 'spec.maxReplicas'],
}


def get_nested_value(data: dict, path: str) -> any:
    """Get a nested value from a dictionary using dot notation"""
    keys = path.split('.')
    value = data
    for key in keys:
        if not isinstance(value, dict) or key not in value:
            return None
        value = value[key]
    return value


def validate_yaml_syntax(file_path: Path) -> Tuple[bool, str, List[Dict]]:
    """Validate YAML syntax and parse the file"""
    try:
        with open(file_path, 'r') as f:
            documents = list(yaml.safe_load_all(f))
            # Filter out None documents (empty YAML docs)
            documents = [doc for doc in documents if doc is not None]
            if not documents:
                return False, f"No valid YAML documents found", []
            return True, "", documents
    except yaml.YAMLError as e:
        return False, f"YAML syntax error: {str(e)}", []
    except Exception as e:
        return False, f"Error reading file: {str(e)}", []


def validate_k8s_structure(doc: Dict, file_path: Path) -> Tuple[bool, List[str]]:
    """Validate Kubernetes resource structure"""
    errors = []

    # Check required fields
    for field in REQUIRED_FIELDS:
        if field not in doc:
            errors.append(f"Missing required field: {field}")

    if errors:
        return False, errors

    # Validate apiVersion
    api_version = doc.get('apiVersion')
    if api_version not in VALID_API_VERSIONS:
        # This is a warning, not an error, as new API versions may exist
        pass

    # Validate kind
    kind = doc.get('kind')
    if kind not in VALID_KINDS:
        errors.append(f"Unknown or unsupported kind: {kind}")

    # Validate metadata
    metadata = doc.get('metadata', {})
    if not isinstance(metadata, dict):
        errors.append("metadata must be a dictionary")
    elif 'name' not in metadata:
        errors.append("metadata.name is required")

    # Resource-specific validations
    if kind in RESOURCE_SPECS:
        for field_path in RESOURCE_SPECS[kind]:
            value = get_nested_value(doc, field_path)
            if value is None:
                errors.append(f"Missing required field for {kind}: {field_path}")

    # Validate spec structure for common resources
    if kind in ['Deployment', 'StatefulSet', 'DaemonSet']:
        spec = doc.get('spec', {})
        template = spec.get('template', {})

        # Check template.metadata
        if not template.get('metadata'):
            errors.append(f"{kind} spec.template.metadata is required")

        # Check template.spec
        template_spec = template.get('spec', {})
        if not template_spec.get('containers'):
            errors.append(f"{kind} spec.template.spec.containers is required")

        # Validate containers
        containers = template_spec.get('containers', [])
        if isinstance(containers, list):
            for i, container in enumerate(containers):
                if not container.get('name'):
                    errors.append(f"{kind} container {i} missing name")
                if not container.get('image'):
                    errors.append(f"{kind} container {i} missing image")

    return len(errors) == 0, errors


def validate_manifests(directory: Path) -> Tuple[int, int, List[str]]:
    """Validate all Kubernetes manifests in a directory"""
    yaml_files = list(directory.glob('*.yaml')) + list(directory.glob('*.yml'))
    # Exclude .gitkeep and other non-manifest files
    yaml_files = [f for f in yaml_files if f.name not in ['.gitkeep']]

    if not yaml_files:
        return 0, 0, ["No YAML files found in directory"]

    total_files = 0
    total_resources = 0
    all_errors = []

    for yaml_file in sorted(yaml_files):
        total_files += 1
        print(f"Validating {yaml_file.name}...", end=" ")

        # Validate YAML syntax
        valid_syntax, syntax_error, documents = validate_yaml_syntax(yaml_file)
        if not valid_syntax:
            print(f"❌ FAILED")
            all_errors.append(f"❌ {yaml_file.name}: {syntax_error}")
            continue

        # Validate each document
        file_valid = True
        for i, doc in enumerate(documents):
            total_resources += 1
            kind = doc.get('kind', 'Unknown')
            name = doc.get('metadata', {}).get('name', 'unnamed')

            valid_structure, errors = validate_k8s_structure(doc, yaml_file)
            if not valid_structure:
                file_valid = False
                doc_identifier = f"document {i}" if len(documents) > 1 else ""
                all_errors.append(f"❌ {yaml_file.name} {doc_identifier} ({kind}/{name}):")
                for error in errors:
                    all_errors.append(f"   - {error}")

        if file_valid:
            print("✅ VALID")
        else:
            print("❌ FAILED")

    return total_files, total_resources, all_errors


def main():
    """Main validation function"""
    if len(sys.argv) > 1:
        manifests_dir = Path(sys.argv[1])
    else:
        manifests_dir = Path(__file__).parent.parent / 'deploy' / 'kubernetes'

    if not manifests_dir.exists():
        print(f"❌ Error: Directory {manifests_dir} does not exist")
        sys.exit(1)

    print(f"Validating Kubernetes manifests in: {manifests_dir}\n")
    print("=" * 70)

    total_files, total_resources, errors = validate_manifests(manifests_dir)

    print("=" * 70)
    print(f"\nValidated {total_files} files containing {total_resources} Kubernetes resources\n")

    if errors:
        print("Validation Errors:\n")
        for error in errors:
            print(error)
        print(f"\n❌ Validation FAILED with {len(errors)} error(s)")
        sys.exit(1)
    else:
        print("✅ All manifests are valid!")
        sys.exit(0)


if __name__ == '__main__':
    main()
