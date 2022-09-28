# GitHub Workflows

Contains reusable GitHub workflows.

To call one of the included workflows from within a different workflow, follow this example:

```yaml
name: main
on:
  pull_request:
    types:
      - opened
      - edited
      - synchronize
      - reopened
jobs:
  validate:
    uses: solvocloud/github-workflows/.github/workflows/main.yml@1.0
    with:
      prTitle: ${{ github.event.pull_request.title }}
    secrets: inherit
```

(Note the `uses`, `with` and `secrets` fields)

**Note**: this repository is public by design. It may be converted to an internal repository in the future.
