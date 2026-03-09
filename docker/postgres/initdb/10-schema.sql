create extension if not exists pgcrypto;

create schema if not exists app;
create schema if not exists billing;
create schema if not exists support;
create schema if not exists analytics;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'user_role') then
    create type app.user_role as enum ('owner', 'admin', 'manager', 'analyst', 'viewer');
  end if;

  if not exists (select 1 from pg_type where typname = 'subscription_status') then
    create type billing.subscription_status as enum ('trialing', 'active', 'past_due', 'canceled');
  end if;

  if not exists (select 1 from pg_type where typname = 'invoice_status') then
    create type billing.invoice_status as enum ('draft', 'issued', 'paid', 'overdue', 'void');
  end if;

  if not exists (select 1 from pg_type where typname = 'payment_status') then
    create type billing.payment_status as enum ('pending', 'succeeded', 'failed', 'refunded');
  end if;

  if not exists (select 1 from pg_type where typname = 'ticket_priority') then
    create type support.ticket_priority as enum ('low', 'medium', 'high', 'urgent');
  end if;

  if not exists (select 1 from pg_type where typname = 'ticket_status') then
    create type support.ticket_status as enum ('new', 'in_progress', 'waiting_on_customer', 'resolved', 'closed');
  end if;
end
$$;

create table if not exists app.organizations (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  legal_name text not null,
  country_code text not null,
  industry text not null,
  company_size integer not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists app.users (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references app.organizations(id) on delete cascade,
  email text not null,
  full_name text not null,
  role app.user_role not null,
  is_active boolean not null default true,
  timezone text not null default 'UTC',
  locale text not null default 'en-US',
  last_login_at timestamptz,
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (organization_id, email)
);

create table if not exists app.projects (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references app.organizations(id) on delete cascade,
  owner_user_id uuid not null references app.users(id),
  code text not null,
  name text not null,
  status text not null,
  budget numeric(12, 2) not null,
  start_date date not null,
  end_date date,
  health_score integer not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (organization_id, code)
);

create table if not exists app.feature_flags (
  id bigserial primary key,
  organization_id uuid not null references app.organizations(id) on delete cascade,
  key text not null,
  enabled boolean not null default false,
  rollout_pct integer not null default 0,
  environments text[] not null default array['production'],
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (organization_id, key)
);

create table if not exists billing.subscriptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null unique references app.organizations(id) on delete cascade,
  plan_name text not null,
  status billing.subscription_status not null,
  monthly_price numeric(12, 2) not null,
  seats integer not null,
  renews_at timestamptz,
  trial_ends_at timestamptz,
  canceled_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists billing.invoices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references app.organizations(id) on delete cascade,
  subscription_id uuid not null references billing.subscriptions(id) on delete cascade,
  invoice_number text not null unique,
  status billing.invoice_status not null,
  issue_date date not null,
  due_date date not null,
  subtotal numeric(12, 2) not null,
  tax numeric(12, 2) not null,
  total numeric(12, 2) not null,
  currency text not null default 'USD',
  paid_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists billing.payments (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references billing.invoices(id) on delete cascade,
  provider text not null,
  status billing.payment_status not null,
  amount numeric(12, 2) not null,
  paid_at timestamptz,
  provider_reference text not null unique,
  raw_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists support.tickets (
  id bigserial primary key,
  organization_id uuid not null references app.organizations(id) on delete cascade,
  project_id uuid references app.projects(id) on delete set null,
  reporter_user_id uuid references app.users(id) on delete set null,
  assignee_user_id uuid references app.users(id) on delete set null,
  title text not null,
  description text not null,
  status support.ticket_status not null,
  priority support.ticket_priority not null,
  source text not null,
  tags text[] not null default '{}',
  custom_fields jsonb not null default '{}'::jsonb,
  opened_at timestamptz not null,
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists support.ticket_comments (
  id bigserial primary key,
  ticket_id bigint not null references support.tickets(id) on delete cascade,
  author_user_id uuid references app.users(id) on delete set null,
  body text not null,
  is_internal boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists app.audit_logs (
  id bigserial primary key,
  organization_id uuid not null references app.organizations(id) on delete cascade,
  actor_user_id uuid references app.users(id) on delete set null,
  entity_type text not null,
  entity_id text not null,
  action text not null,
  changes jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);

create table if not exists analytics.page_views (
  id bigserial primary key,
  organization_id uuid not null references app.organizations(id) on delete cascade,
  project_id uuid references app.projects(id) on delete set null,
  visitor_id uuid not null,
  path text not null,
  referrer text,
  country_code text not null,
  duration_seconds integer not null,
  occurred_at timestamptz not null
);

create index if not exists idx_users_org on app.users(organization_id);
create index if not exists idx_projects_org on app.projects(organization_id);
create index if not exists idx_projects_owner on app.projects(owner_user_id);
create index if not exists idx_feature_flags_org on app.feature_flags(organization_id);
create index if not exists idx_invoices_org on billing.invoices(organization_id, issue_date desc);
create index if not exists idx_invoices_status on billing.invoices(status);
create index if not exists idx_payments_invoice on billing.payments(invoice_id);
create index if not exists idx_tickets_org on support.tickets(organization_id, opened_at desc);
create index if not exists idx_tickets_status on support.tickets(status, priority);
create index if not exists idx_ticket_comments_ticket on support.ticket_comments(ticket_id, created_at);
create index if not exists idx_audit_logs_org on app.audit_logs(organization_id, occurred_at desc);
create index if not exists idx_page_views_org on analytics.page_views(organization_id, occurred_at desc);
create index if not exists idx_page_views_project on analytics.page_views(project_id, occurred_at desc);
