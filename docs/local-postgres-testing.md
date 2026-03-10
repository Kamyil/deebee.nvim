# Local PostgreSQL Testing

This repository includes a seeded PostgreSQL Docker image for realistic plugin testing.

The dataset is intentionally closer to a real SaaS workspace than a toy schema. It includes multiple schemas, views, a materialized view, JSONB columns, enums, arrays, timestamps, foreign keys, and enough rows to exercise browsing and query-running paths.

## What Is Included

Schemas:

- `app`
- `billing`
- `support`
- `analytics`

Representative objects:

- organizations, users, projects, feature flags
- subscriptions, invoices, payments
- tickets, ticket comments
- audit logs
- page views
- reporting views and a materialized view

## Default Connection

The local test database uses:

```text
postgres://deebee:deebee@localhost:55432/deebee
```

## Justfile Commands

From the repository root:

```bash
just pg-run
just pg-reset
just pg-status
just pg-logs
just pg-psql
just pg-query "select count(*) from app.organizations;"
just pg-url
```

## Recommended Plugin Smoke Queries

Basic table browsing:

```sql
select * from app.organizations order by created_at desc limit 25;
select * from app.users order by created_at desc limit 50;
select * from app.projects order by health_score desc limit 50;
```

Views and reporting:

```sql
select * from analytics.organization_overview order by paid_revenue desc limit 20;
select * from billing.outstanding_invoices order by days_past_due desc limit 20;
select * from support.open_ticket_queue order by opened_at asc limit 20;
select * from analytics.daily_revenue order by issue_date desc limit 20;
```

Join-heavy inspection queries:

```sql
select
  org.slug,
  prj.code,
  t.title,
  t.status,
  t.priority,
  assignee.full_name as assignee
from support.tickets t
join app.organizations org on org.id = t.organization_id
left join app.projects prj on prj.id = t.project_id
left join app.users assignee on assignee.id = t.assignee_user_id
order by t.opened_at desc
limit 50;
```

Editable-grid-friendly examples for the local PoC:

```sql
select * from app.feature_flags order by id limit 100;
select id, organization_id, key, enabled, rollout_pct, environments from app.feature_flags order by id limit 100;
select * from support.tickets order by id limit 100;
```

After running one of those, switch to the results pane and try:

- `e` to enter edit mode
- `<CR>` to edit a cell
- `gC` to open the pending-changes review (then `a` to apply locally)
- `gR` to roll back staged local changes
