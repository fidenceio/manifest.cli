# Manifest CLI Examples

## Patch Release (Local Prep)

```bash
git add .
git commit -m "fix: address edge case"
manifest test all
manifest prep patch
```

## Publish Release

```bash
manifest ship minor
```

## Regenerate Docs Only

```bash
manifest docs
manifest docs metadata
```

## PR Queue Flow

```bash
manifest pr status
manifest pr checks
manifest pr ready
manifest pr queue
```

## Fleet Coordination

```bash
manifest fleet discover
manifest fleet status
manifest fleet sync
manifest fleet ship
```

## Cloud and Agent Checks

```bash
manifest test cloud
manifest cloud status
manifest agent status
```

## Configuration Workflow

```bash
manifest config setup
manifest config show
manifest config time
```

## Safe Maintenance

```bash
manifest upgrade --check
manifest security
manifest cleanup
```
