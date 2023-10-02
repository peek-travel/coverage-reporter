# CoverageReporter

## Usage

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

