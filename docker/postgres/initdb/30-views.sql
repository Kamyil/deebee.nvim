create or replace view app.organization_directory as
select
  org.id,
  org.slug,
  org.name,
  org.industry,
  org.country_code,
  org.company_size,
  count(distinct usr.id) as user_count,
  count(distinct prj.id) as project_count,
  sub.plan_name,
  sub.status as subscription_status,
  sub.monthly_price,
  org.created_at
from app.organizations org
left join app.users usr on usr.organization_id = org.id
left join app.projects prj on prj.organization_id = org.id
left join billing.subscriptions sub on sub.organization_id = org.id
group by org.id, sub.id;

create or replace view billing.outstanding_invoices as
select
  inv.id,
  inv.invoice_number,
  org.slug as organization_slug,
  org.name as organization_name,
  inv.status,
  inv.issue_date,
  inv.due_date,
  inv.total,
  greatest((current_date - inv.due_date), 0) as days_past_due
from billing.invoices inv
join app.organizations org on org.id = inv.organization_id
where inv.status in ('issued', 'overdue')
order by inv.due_date asc;

create or replace view support.open_ticket_queue as
select
  t.id,
  org.slug as organization_slug,
  prj.code as project_code,
  t.title,
  t.status,
  t.priority,
  reporter.full_name as reporter_name,
  assignee.full_name as assignee_name,
  t.opened_at,
  extract(epoch from (now() - t.opened_at)) / 3600 as hours_open
from support.tickets t
join app.organizations org on org.id = t.organization_id
left join app.projects prj on prj.id = t.project_id
left join app.users reporter on reporter.id = t.reporter_user_id
left join app.users assignee on assignee.id = t.assignee_user_id
where t.status in ('new', 'in_progress', 'waiting_on_customer')
order by t.priority desc, t.opened_at asc;

create or replace view analytics.organization_overview as
select
  org.id,
  org.slug,
  org.name,
  count(distinct usr.id) as users_total,
  count(distinct prj.id) as projects_total,
  count(distinct case when t.status in ('new', 'in_progress', 'waiting_on_customer') then t.id end) as open_tickets,
  coalesce(sum(case when inv.status = 'paid' then inv.total end), 0)::numeric(14, 2) as paid_revenue,
  coalesce(sum(case when inv.status in ('issued', 'overdue') then inv.total end), 0)::numeric(14, 2) as outstanding_revenue,
  max(pv.occurred_at) as last_page_view_at
from app.organizations org
left join app.users usr on usr.organization_id = org.id
left join app.projects prj on prj.organization_id = org.id
left join support.tickets t on t.organization_id = org.id
left join billing.invoices inv on inv.organization_id = org.id
left join analytics.page_views pv on pv.organization_id = org.id
group by org.id;

create materialized view analytics.daily_revenue as
select
  inv.issue_date,
  inv.organization_id,
  org.slug as organization_slug,
  count(*) as invoices_total,
  sum(inv.total)::numeric(14, 2) as total_revenue,
  sum(case when inv.status = 'paid' then inv.total else 0 end)::numeric(14, 2) as paid_revenue,
  sum(case when inv.status in ('issued', 'overdue') then inv.total else 0 end)::numeric(14, 2) as outstanding_revenue
from billing.invoices inv
join app.organizations org on org.id = inv.organization_id
group by inv.issue_date, inv.organization_id, org.slug;

create index if not exists idx_daily_revenue_date on analytics.daily_revenue(issue_date desc);
