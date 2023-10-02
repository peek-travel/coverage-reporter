# CoverageReporter

## Usage

```yaml
- name: Coverage Reporter
  uses: peek-travel/coverage-reporter@main
  id: coverage-reporter
  if: github.event_name == 'pull_request'
  with: 
    pull-number: ${{ github.event.number }}
    repository: ${{ github.repository }}
    head-branch: ${{ github.head_ref }}
```