# CoverageReporter

A GitHub Action that analyzes code coverage from LCOV files and creates annotations on pull requests.

## Usage

### Basic Usage

```yaml
- name: Coverage Reporter
  uses: peek-travel/coverage-reporter@main
  id: coverage-reporter
  if: github.event_name == 'pull_request'
  with:
    pull_number: ${{ github.event.number }}
    repository: ${{ github.repository }}
    head_branch: ${{ github.head_ref }}
    lcov_path: cover/**-lcov.info
    coverage_threshold: 80
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `coverage_threshold` | Minimum coverage percentage required | Yes | `80` |
| `lcov_path` | Path to LCOV file(s). Supports wildcards. | Yes | - |
| `lcov_path_prefix` | Prefix to remove from file paths in reports | No | `""` |

