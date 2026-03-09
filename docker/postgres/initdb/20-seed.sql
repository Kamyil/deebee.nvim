insert into app.organizations (slug, name, legal_name, country_code, industry, company_size, metadata, created_at)
select
  'org-' || lpad(gs::text, 2, '0'),
  initcap((array['northwind', 'sunpeak', 'lattice', 'harbor', 'orbit', 'summit', 'ember', 'canopy'])[1 + ((gs - 1) % 8)]) || ' ' ||
    initcap((array['systems', 'analytics', 'cloud', 'labs', 'commerce', 'health', 'security', 'energy'])[1 + (((gs - 1) / 2) % 8)]),
  initcap((array['northwind', 'sunpeak', 'lattice', 'harbor', 'orbit', 'summit', 'ember', 'canopy'])[1 + ((gs - 1) % 8)]) || ' Holdings LLC',
  (array['US', 'DE', 'GB', 'PL', 'CA', 'AU'])[1 + ((gs - 1) % 6)],
  (array['SaaS', 'Retail', 'Healthcare', 'Fintech', 'Logistics', 'Manufacturing'])[1 + ((gs - 1) % 6)],
  20 + gs * 8,
  jsonb_build_object(
    'tier', (array['startup', 'growth', 'enterprise'])[1 + ((gs - 1) % 3)],
    'sales_region', (array['na', 'emea', 'apac'])[1 + ((gs - 1) % 3)],
    'customer_success_owner', 'csm-' || lpad(gs::text, 2, '0')
  ),
  now() - ((60 + gs * 7) * interval '1 day')
from generate_series(1, 24) as gs;

with organization_rows as (
  select id, slug, row_number() over (order by slug) as org_n
  from app.organizations
)
insert into app.users (
  organization_id,
  email,
  full_name,
  role,
  is_active,
  timezone,
  locale,
  last_login_at,
  settings,
  created_at
)
select
  org.id,
  'user' || lpad(org.org_n::text, 2, '0') || '_' || lpad(user_n::text, 2, '0') || '@' || org.slug || '.example',
  initcap((array['alex', 'morgan', 'sam', 'jamie', 'riley', 'casey', 'taylor', 'jordan', 'devon', 'avery'])[1 + ((user_n - 1) % 10)]) || ' ' ||
    initcap((array['walker', 'rivera', 'patel', 'nguyen', 'kim', 'cooper', 'howard', 'foster', 'brooks', 'ross'])[1 + ((org.org_n + user_n - 2) % 10)]),
  case
    when user_n = 1 then 'owner'::app.user_role
    when user_n <= 3 then 'admin'::app.user_role
    when user_n <= 7 then 'manager'::app.user_role
    when user_n <= 12 then 'analyst'::app.user_role
    else 'viewer'::app.user_role
  end,
  user_n % 13 <> 0,
  (array['UTC', 'Europe/Berlin', 'Europe/Warsaw', 'America/New_York', 'America/Los_Angeles'])[1 + ((user_n - 1) % 5)],
  (array['en-US', 'en-GB', 'pl-PL', 'de-DE'])[1 + ((org.org_n + user_n - 2) % 4)],
  now() - ((user_n % 20) * interval '1 day') - ((user_n % 9) * interval '1 hour'),
  jsonb_build_object(
    'theme', (array['kanagawa', 'everforest', 'tokyonight', 'mellifluous'])[1 + ((user_n - 1) % 4)],
    'dashboard_layout', (array['compact', 'standard', 'operations'])[1 + ((org.org_n + user_n - 2) % 3)]
  ),
  now() - ((90 + user_n + org.org_n) * interval '1 day')
from organization_rows org
cross join generate_series(1, 18) as user_n;

with organization_rows as (
  select id, slug, row_number() over (order by slug) as org_n
  from app.organizations
), owner_rows as (
  select organization_id, id, row_number() over (partition by organization_id order by email) as rn
  from app.users
)
insert into app.projects (
  organization_id,
  owner_user_id,
  code,
  name,
  status,
  budget,
  start_date,
  end_date,
  health_score,
  metadata,
  created_at
)
select
  org.id,
  owner.id,
  'PRJ-' || lpad(org.org_n::text, 2, '0') || '-' || lpad(project_n::text, 2, '0'),
  initcap((array['customer portal', 'internal api', 'sales hub', 'mobile app', 'warehouse sync', 'fraud monitor'])[project_n]),
  (array['planned', 'active', 'at_risk', 'paused', 'completed'])[1 + ((org.org_n + project_n - 2) % 5)],
  (20000 + org.org_n * 3500 + project_n * 4200)::numeric(12, 2),
  (current_date - (((project_n * 20) + org.org_n) * interval '1 day'))::date,
  case when project_n % 5 = 0 then (current_date + ((project_n * 15) * interval '1 day'))::date else null end,
  55 + ((org.org_n * 7 + project_n * 9) % 45),
  jsonb_build_object(
    'environment', (array['production', 'staging', 'beta'])[1 + ((project_n - 1) % 3)],
    'team', (array['platform', 'growth', 'payments', 'ops'])[1 + ((project_n - 1) % 4)]
  ),
  now() - ((100 + org.org_n * 3 + project_n) * interval '1 day')
from organization_rows org
cross join generate_series(1, 6) as project_n
join owner_rows owner on owner.organization_id = org.id and owner.rn = ((project_n - 1) % 6) + 1;

with organization_rows as (
  select id, slug, row_number() over (order by slug) as org_n
  from app.organizations
)
insert into app.feature_flags (organization_id, key, enabled, rollout_pct, environments, payload, created_at)
select
  org.id,
  flag.key,
  ((org.org_n + flag.flag_n) % 3 <> 0),
  (10 + (((org.org_n * 17) + (flag.flag_n * 13)) % 91)),
  flag.environments,
  jsonb_build_object('owner', flag.owner, 'notes', flag.notes),
  now() - ((30 + org.org_n + flag.flag_n) * interval '1 day')
from organization_rows org
cross join (
  values
    ('smart-search', 1, array['staging', 'production'], 'platform', 'Rollout for vector search.'),
    ('new-billing-ui', 2, array['beta', 'production'], 'growth', 'Refresh of account billing area.'),
    ('case-routing-v2', 3, array['staging'], 'support', 'Support queue scoring experiment.'),
    ('usage-based-alerts', 4, array['production'], 'ops', 'Threshold based spend alerts.')
) as flag(key, flag_n, environments, owner, notes);

insert into billing.subscriptions (
  organization_id,
  plan_name,
  status,
  monthly_price,
  seats,
  renews_at,
  trial_ends_at,
  canceled_at,
  created_at
)
select
  org.id,
  (array['starter', 'growth', 'scale', 'enterprise'])[1 + ((row_number() over (order by org.slug) - 1) % 4)],
  case
    when row_number() over (order by org.slug) % 11 = 0 then 'past_due'::billing.subscription_status
    when row_number() over (order by org.slug) % 13 = 0 then 'canceled'::billing.subscription_status
    when row_number() over (order by org.slug) % 5 = 0 then 'trialing'::billing.subscription_status
    else 'active'::billing.subscription_status
  end,
  (299 + (row_number() over (order by org.slug) - 1) * 79)::numeric(12, 2),
  org.company_size,
  now() + ((30 - (row_number() over (order by org.slug) % 8)) * interval '1 day'),
  now() + ((14 - (row_number() over (order by org.slug) % 6)) * interval '1 day'),
  case when row_number() over (order by org.slug) % 13 = 0 then now() - interval '22 days' else null end,
  org.created_at + interval '2 days'
from app.organizations org;

with subscription_rows as (
  select s.id, s.organization_id, s.monthly_price, row_number() over (order by o.slug) as org_n
  from billing.subscriptions s
  join app.organizations o on o.id = s.organization_id
)
insert into billing.invoices (
  organization_id,
  subscription_id,
  invoice_number,
  status,
  issue_date,
  due_date,
  subtotal,
  tax,
  total,
  currency,
  paid_at,
  created_at
)
select
  s.organization_id,
  s.id,
  'INV-' || lpad(s.org_n::text, 2, '0') || '-' || lpad(month_n::text, 4, '0'),
  case
    when month_n = 12 then 'issued'::billing.invoice_status
    when (s.org_n + month_n) % 7 = 0 then 'overdue'::billing.invoice_status
    else 'paid'::billing.invoice_status
  end,
  date_trunc('month', current_date - ((12 - month_n) * interval '1 month'))::date,
  (date_trunc('month', current_date - ((12 - month_n) * interval '1 month')) + interval '14 days')::date,
  s.monthly_price,
  round(s.monthly_price * 0.21, 2),
  round(s.monthly_price * 1.21, 2),
  'USD',
  case
    when month_n = 12 then null
    when (s.org_n + month_n) % 7 = 0 then null
    else date_trunc('month', current_date - ((12 - month_n) * interval '1 month')) + interval '5 days'
  end,
  date_trunc('month', current_date - ((12 - month_n) * interval '1 month')) + interval '1 day'
from subscription_rows s
cross join generate_series(1, 12) as month_n;

insert into billing.payments (
  invoice_id,
  provider,
  status,
  amount,
  paid_at,
  provider_reference,
  raw_payload,
  created_at
)
select
  invoice.id,
  (array['stripe', 'adyen', 'braintree'])[1 + ((row_number() over (order by invoice.invoice_number) - 1) % 3)],
  case
    when invoice.status = 'paid' then 'succeeded'::billing.payment_status
    when invoice.status = 'overdue' and row_number() over (order by invoice.invoice_number) % 4 = 0 then 'failed'::billing.payment_status
    else 'pending'::billing.payment_status
  end,
  invoice.total,
  invoice.paid_at,
  format('pay_%s', replace(invoice.invoice_number, '-', '_')),
  jsonb_build_object('attempt_count', 1 + ((row_number() over (order by invoice.invoice_number) - 1) % 3), 'currency', invoice.currency),
  invoice.created_at + interval '2 hours'
from billing.invoices invoice
where invoice.status in ('paid', 'overdue', 'issued');

with organization_rows as (
  select id, slug, row_number() over (order by slug) as org_n
  from app.organizations
), ranked_users as (
  select organization_id, id, row_number() over (partition by organization_id order by email) as rn
  from app.users
), ranked_projects as (
  select organization_id, id, row_number() over (partition by organization_id order by code) as rn
  from app.projects
)
insert into support.tickets (
  organization_id,
  project_id,
  reporter_user_id,
  assignee_user_id,
  title,
  description,
  status,
  priority,
  source,
  tags,
  custom_fields,
  opened_at,
  resolved_at,
  created_at
)
select
  org.id,
  project.id,
  reporter.id,
  assignee.id,
  initcap((array['checkout failure', 'permissions mismatch', 'sync lag', 'missing report', 'api timeout', 'invoice discrepancy'])[1 + ((ticket_n - 1) % 6)]) || ' #' || ticket_n,
  'Customer reported issue in day-to-day workflow. Ticket seeded for plugin exploration and join/query testing.',
  (array['new', 'in_progress', 'waiting_on_customer', 'resolved', 'closed'])[1 + ((org.org_n + ticket_n - 2) % 5)]::support.ticket_status,
  (array['low', 'medium', 'high', 'urgent'])[1 + ((ticket_n - 1) % 4)]::support.ticket_priority,
  (array['email', 'slack', 'api', 'in_app'])[1 + ((org.org_n + ticket_n - 2) % 4)],
  array[
    (array['billing', 'auth', 'reporting', 'warehouse', 'notifications'])[1 + ((ticket_n - 1) % 5)],
    (array['vip', 'migration', 'trial', 'renewal', 'integration'])[1 + ((org.org_n + ticket_n - 2) % 5)]
  ],
  jsonb_build_object('impacted_users', 1 + ((ticket_n * 3) % 20), 'sla_minutes', 30 + ((ticket_n * 17) % 240)),
  now() - ((35 - (ticket_n % 20)) * interval '1 day') - ((ticket_n % 10) * interval '1 hour'),
  case when (org.org_n + ticket_n) % 5 in (3, 4) then now() - ((ticket_n % 8) * interval '1 day') else null end,
  now() - ((40 - (ticket_n % 20)) * interval '1 day') - ((ticket_n % 10) * interval '1 hour')
from organization_rows org
cross join generate_series(1, 25) as ticket_n
join ranked_projects project on project.organization_id = org.id and project.rn = ((ticket_n - 1) % 6) + 1
join ranked_users reporter on reporter.organization_id = org.id and reporter.rn = ((ticket_n - 1) % 18) + 1
join ranked_users assignee on assignee.organization_id = org.id and assignee.rn = ((ticket_n + 4) % 18) + 1;

with ranked_users as (
  select organization_id, id, row_number() over (partition by organization_id order by email) as rn
  from app.users
), ranked_tickets as (
  select t.id, t.organization_id, row_number() over (partition by t.organization_id order by t.id) as rn, t.created_at
  from support.tickets t
)
insert into support.ticket_comments (
  ticket_id,
  author_user_id,
  body,
  is_internal,
  created_at
)
select
  ticket.id,
  author.id,
  (array[
    'Investigated logs and attached context for follow-up.',
    'Customer confirmed this is reproducible in production only.',
    'Escalated to product engineering for root-cause analysis.',
    'Applied mitigation and requested another validation pass.'
  ])[1 + ((comment_n - 1) % 4)],
  comment_n % 3 = 0,
  ticket.created_at + ((comment_n * 3) * interval '1 hour')
from ranked_tickets ticket
cross join generate_series(1, 3) as comment_n
join ranked_users author on author.organization_id = ticket.organization_id and author.rn = ((ticket.rn + comment_n - 2) % 18) + 1;

with organization_rows as (
  select id, row_number() over (order by slug) as org_n
  from app.organizations
), ranked_users as (
  select organization_id, id, row_number() over (partition by organization_id order by email) as rn
  from app.users
)
insert into app.audit_logs (
  organization_id,
  actor_user_id,
  entity_type,
  entity_id,
  action,
  changes,
  occurred_at
)
select
  org.id,
  actor.id,
  (array['project', 'subscription', 'ticket', 'feature_flag'])[1 + ((event_n - 1) % 4)],
  'entity-' || lpad(org.org_n::text, 2, '0') || '-' || lpad(event_n::text, 3, '0'),
  (array['created', 'updated', 'archived', 'commented'])[1 + ((org.org_n + event_n - 2) % 4)],
  jsonb_build_object('field', (array['status', 'budget', 'assignee', 'rollout_pct'])[1 + ((event_n - 1) % 4)], 'source', 'seed'),
  now() - ((event_n % 30) * interval '1 day') - ((event_n % 12) * interval '1 hour')
from organization_rows org
cross join generate_series(1, 40) as event_n
join ranked_users actor on actor.organization_id = org.id and actor.rn = ((event_n - 1) % 18) + 1;

with organization_rows as (
  select id, row_number() over (order by slug) as org_n
  from app.organizations
), ranked_projects as (
  select organization_id, id, row_number() over (partition by organization_id order by code) as rn
  from app.projects
)
insert into analytics.page_views (
  organization_id,
  project_id,
  visitor_id,
  path,
  referrer,
  country_code,
  duration_seconds,
  occurred_at
)
select
  org.id,
  project.id,
  gen_random_uuid(),
  (array['/dashboard', '/reports/revenue', '/reports/retention', '/settings/billing', '/projects', '/support/tickets'])[1 + ((view_n - 1) % 6)],
  (array['https://google.com', 'https://news.ycombinator.com', 'https://linkedin.com', null])[1 + ((view_n - 1) % 4)],
  (array['US', 'DE', 'GB', 'PL', 'CA', 'AU'])[1 + ((org.org_n + view_n - 2) % 6)],
  20 + ((view_n * 11) % 600),
  now() - ((view_n % 28) * interval '1 day') - ((view_n % 24) * interval '1 hour') - ((view_n % 60) * interval '1 minute')
from organization_rows org
cross join generate_series(1, 150) as view_n
join ranked_projects project on project.organization_id = org.id and project.rn = ((view_n - 1) % 6) + 1;
