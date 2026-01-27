-- ============================================================
-- POST BOOKING FLOW TABLES
-- Run this in your Supabase SQL Editor
-- ============================================================

-- SERVICE REQUESTS (posted by clients for workers to apply)
create table if not exists public.service_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.users(id) on delete cascade,
  service_type text not null,
  description text,
  location text,
  latitude double precision,
  longitude double precision,
  budget_min double precision default 0,
  budget_max double precision default 0,
  preferred_date timestamptz,
  status text check (status in ('open', 'closed', 'assigned', 'cancelled')) default 'open',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- JOB APPLICATIONS (workers applying to service requests)
create table if not exists public.job_applications (
  id uuid primary key default gen_random_uuid(),
  request_id uuid references public.service_requests(id) on delete cascade,
  worker_id uuid references public.users(id) on delete cascade,
  rate_offer double precision,
  note text,
  status text check (status in ('pending', 'accepted', 'rejected')) default 'pending',
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique(request_id, worker_id) -- Prevent duplicate applications
);

-- Indexes for better performance
create index if not exists service_requests_status_idx on public.service_requests(status);
create index if not exists service_requests_user_idx on public.service_requests(user_id);
create index if not exists job_applications_request_idx on public.job_applications(request_id);
create index if not exists job_applications_worker_idx on public.job_applications(worker_id);
create index if not exists job_applications_status_idx on public.job_applications(status);

-- Enable RLS
alter table public.service_requests enable row level security;
alter table public.job_applications enable row level security;

-- RLS POLICIES FOR SERVICE_REQUESTS
do $$
begin
  -- Anyone authenticated can view open service requests
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='service_requests' and policyname='service_requests_select_open'
  ) then
    create policy service_requests_select_open on public.service_requests
      for select to authenticated
      using (status = 'open' or user_id = auth.uid());
  end if;

  -- Clients can insert their own requests
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='service_requests' and policyname='service_requests_insert_own'
  ) then
    create policy service_requests_insert_own on public.service_requests
      for insert to authenticated
      with check (user_id = auth.uid());
  end if;

  -- Clients can update their own requests
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='service_requests' and policyname='service_requests_update_own'
  ) then
    create policy service_requests_update_own on public.service_requests
      for update to authenticated
      using (user_id = auth.uid())
      with check (user_id = auth.uid());
  end if;
end$$;

-- RLS POLICIES FOR JOB_APPLICATIONS
do $$
begin
  -- Workers can view applications for requests they applied to
  -- Clients can view applications for their requests
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='job_applications' and policyname='job_applications_select_related'
  ) then
    create policy job_applications_select_related on public.job_applications
      for select to authenticated
      using (
        worker_id = auth.uid() or
        exists (
          select 1 from public.service_requests
          where id = job_applications.request_id and user_id = auth.uid()
        )
      );
  end if;

  -- Workers can insert their own applications
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='job_applications' and policyname='job_applications_insert_worker'
  ) then
    create policy job_applications_insert_worker on public.job_applications
      for insert to authenticated
      with check (worker_id = auth.uid());
  end if;

  -- Clients can update applications for their requests
  -- Workers can update their own applications (to withdraw)
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='job_applications' and policyname='job_applications_update_related'
  ) then
    create policy job_applications_update_related on public.job_applications
      for update to authenticated
      using (
        worker_id = auth.uid() or
        exists (
          select 1 from public.service_requests
          where id = job_applications.request_id and user_id = auth.uid()
        )
      );
  end if;
end$$;

-- Add helpful comment
comment on table public.service_requests is 'Service requests posted by clients for workers to browse and apply';
comment on table public.job_applications is 'Worker applications to service requests';


