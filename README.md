# devsnap

[![CI](https://github.com/ikraamg/devsnap/actions/workflows/ci.yml/badge.svg)](https://github.com/ikraamg/devsnap/actions/workflows/ci.yml)

Zero-friction DB snapshots for Rails development. Auto-captures before migrations, so you can undo anything.

## Install (30 seconds)

```bash
curl -sSL https://raw.githubusercontent.com/ikraamg/devsnap/main/devsnap.rake \
  -o lib/tasks/devsnap.rake && echo ".snapshots/" >> .gitignore
```

That's it. Next time you run `rails db:migrate`, it auto-snapshots first.

## Usage

**It just works:**
```bash
rails db:migrate                    # Auto-snapshots before migrating
```

**Manual commands:**
```bash
rails devsnap:list                  # See your snapshots
rails devsnap:capture[name]         # Manual snapshot
rails devsnap:restore[name]         # Restore snapshot
```

## Requirements

- Rails 6.1+
- PostgreSQL
- Development environment only

## Configuration

All optional via environment variables:

- `DEVSNAP=off` - Disable for one command
- `DEVSNAP_KEEP=10` - Number of snapshots to keep (default: 5)
- `DEVSNAP_MAX_MB=1000` - Max DB size in MB (default: 500)
- `FORCE_SNAP=1` - Ignore size limit

## Examples

```bash
# Skip auto-snapshot for this migration
DEVSNAP=off rails db:migrate

# Keep more snapshots
DEVSNAP_KEEP=10 rails db:migrate

# Force snapshot of large database
FORCE_SNAP=1 rails devsnap:capture[before_risk]

# Restore from yesterday
rails devsnap:list
rails devsnap:restore[20240123_143022]
```

## Uninstall

```bash
rm lib/tasks/devsnap.rake
rm -rf .snapshots/
```

## How it works

- Hooks into `db:migrate` in development only
- Before running pending migrations, captures DB with `pg_dump -Fc`
- Names snapshots with timestamp: `pre_migrate_1708789234.dump`
- Auto-prunes old snapshots (keeps last 5)
- Skips large databases (>500MB) automatically
- Silent operation - doesn't disrupt your workflow

## License

MIT