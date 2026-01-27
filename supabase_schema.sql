-- Supabase Schema for SerbisyoKo
-- Run in Supabase SQL editor. Creates tables, indexes, and RLS policies.

-- Extensions
create extension if not exists pgcrypto;

-- USERS (mirror of auth.users)
create table if not exists public.users (
  id uuid primary key default auth.uid(),
  email text unique,
  name text,
  phone text,
  role text check (role in ('Admin','Worker','Client')) default 'Client',
  created_at timestamptz default now()
);

-- WORKER PROFILES
create table if not exists public.worker_profiles (
  user_id uuid primary key references public.users(id) on delete cascade,
  about text,
  hourly_rate integer default 0,
  is_verified boolean default false,
  verification_status text check (verification_status in ('pending','approved','rejected')) default 'pending',
  service_area text, -- e.g., district/barangay
  lat double precision, -- optional precise
  lng double precision,
  availability_status text check (availability_status in ('OFF','ON')) default 'OFF',
  documents jsonb default '[]'::jsonb, -- uploaded file metadata from storage
  verification_notes text, -- admin notes for verification
  verified_at timestamptz, -- when verification was completed
  verified_by uuid references public.users(id), -- admin who verified
  updated_at timestamptz default now()
);

-- SERVICES CATALOG
create table if not exists public.services (
  id uuid primary key default gen_random_uuid(),
  name text unique not null,
  category text,
  created_at timestamptz default now()
);

-- WORKER SKILLS (many-to-many)
create table if not exists public.worker_skills (
  worker_id uuid references public.users(id) on delete cascade,
  service_id uuid references public.services(id) on delete cascade,
  level int check (level between 1 and 5) default 3,
  primary key(worker_id, service_id)
);

-- SIDE GIGS (posted by workers)
create table if not exists public.gigs (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid references public.users(id) on delete cascade,
  title text not null,
  description text,
  price integer,
  location text,
  lat double precision,
  lng double precision,
  created_at timestamptz default now()
);

-- BOOKINGS
create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  client_id uuid references public.users(id) on delete set null,
  worker_id uuid references public.users(id) on delete set null,
  service_type text not null,
  scheduled_time timestamptz not null,
  location text,
  lat double precision,
  lng double precision,
  booking_fee integer default 0,
  estimated_price integer default 0,
  mode_of_payment text,
  status text check (status in ('Pending','Accepted','InProgress','Completed','Cancelled')) default 'Pending',
  created_at timestamptz default now()
);
create index if not exists bookings_by_client on public.bookings(client_id);
create index if not exists bookings_by_worker on public.bookings(worker_id);

-- RATINGS
create table if not exists public.ratings (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid references public.bookings(id) on delete cascade,
  rater_id uuid references public.users(id) on delete set null,
  worker_id uuid references public.users(id) on delete set null,
  score int check (score between 1 and 5) not null,
  comment text,
  created_at timestamptz default now(),
  unique (booking_id, rater_id)
);

-- BASIC RLS
alter table public.users enable row level security;
alter table public.worker_profiles enable row level security;
alter table public.worker_skills enable row level security;
alter table public.services enable row level security;
alter table public.gigs enable row level security;
alter table public.bookings enable row level security;
alter table public.ratings enable row level security;

-- USERS policies
do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='users' and policyname='users_select_auth'
  ) then
    create policy users_select_auth on public.users for select
      to authenticated using (true);
  end if;
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='users' and policyname='users_insert_self'
  ) then
    create policy users_insert_self on public.users for insert
      to authenticated with check (id = auth.uid());
  end if;
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='users' and policyname='users_update_self'
  ) then
    create policy users_update_self on public.users for update
      to authenticated using (id = auth.uid()) with check (id = auth.uid());
  end if;
end$$;

-- WORKER PROFILES policies
do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='worker_profiles' and policyname='wp_select_all'
  ) then
    create policy wp_select_all on public.worker_profiles for select to authenticated using (true);
  end if;
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='worker_profiles' and policyname='wp_upsert_self'
  ) then
    create policy wp_upsert_self on public.worker_profiles for all
      to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
  end if;
end$$;

-- SERVICES policies (read-only to all; write restricted later by admin role)
do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='services' and policyname='services_select_all'
  ) then
    create policy services_select_all on public.services for select to authenticated using (true);
  end if;
end$$;

-- WORKER SKILLS policies
do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='worker_skills' and policyname='skills_select_all'
  ) then
    create policy skills_select_all on public.worker_skills for select to authenticated using (true);
  end if;
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='worker_skills' and policyname='skills_modify_self'
  ) then
    create policy skills_modify_self on public.worker_skills for all to authenticated
      using (worker_id = auth.uid()) with check (worker_id = auth.uid());
  end if;
end$$;

-- GIGS policies
do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='gigs' and policyname='gigs_select_all'
  ) then
    create policy gigs_select_all on public.gigs for select to authenticated using (true);
  end if;
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='gigs' and policyname='gigs_modify_self'
  ) then
    create policy gigs_modify_self on public.gigs for all to authenticated
      using (worker_id = auth.uid()) with check (worker_id = auth.uid());
  end if;
end$$;

-- BOOKINGS policies
do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='bookings' and policyname='bookings_select_related'
  ) then
    create policy bookings_select_related on public.bookings for select to authenticated
      using (client_id = auth.uid() or worker_id = auth.uid());
  end if;
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='bookings' and policyname='bookings_insert_client'
  ) then
    create policy bookings_insert_client on public.bookings for insert to authenticated
      with check (client_id = auth.uid());
  end if;
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='bookings' and policyname='bookings_update_related'
  ) then
    create policy bookings_update_related on public.bookings for update to authenticated
      using (client_id = auth.uid() or worker_id = auth.uid());
  end if;
end$$;

-- RATINGS policies
do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='ratings' and policyname='ratings_select_all'
  ) then
    create policy ratings_select_all on public.ratings for select to authenticated using (true);
  end if;
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='ratings' and policyname='ratings_insert_client'
  ) then
    create policy ratings_insert_client on public.ratings for insert to authenticated
      with check (rater_id = auth.uid());
  end if;
end$$;

-- Create storage bucket for verification documents
insert into storage.buckets (id, name, public)
  values ('verification-documents', 'verification-documents', false)
  on conflict (id) do nothing;

-- Storage policies for verification documents
create policy "Users can upload their own verification documents"
  on storage.objects for insert
  with check (bucket_id = 'verification-documents' and auth.uid()::text = (storage.foldername(name))[1]);

create policy "Users can view their own verification documents"
  on storage.objects for select
  using (bucket_id = 'verification-documents' and auth.uid()::text = (storage.foldername(name))[1]);

create policy "Admins can view all verification documents"
  on storage.objects for select
  using (bucket_id = 'verification-documents' and exists (
    select 1 from public.users where id = auth.uid() and role = 'Admin'
  ));

-- Admin policies for worker verification
create policy "admins_can_verify_workers" on public.worker_profiles
  for update to authenticated
  using (exists (
    select 1 from public.users where id = auth.uid() and role = 'Admin'
  ))
  with check (exists (
    select 1 from public.users where id = auth.uid() and role = 'Admin'
  ));

-- Helpful seed services
insert into public.services (name, category)
  values ('Plumber','Home Repair') on conflict do nothing;
insert into public.services (name, category)
  values ('Electrician','Home Repair') on conflict do nothing;
insert into public.services (name, category)
  values ('Aircon Technician','Appliances') on conflict do nothing;
insert into public.services (name, category)
  values ('House Cleaning','Cleaning') on conflict do nothing;
insert into public.services (name, category)
  values ('Carpentry','Home Repair') on conflict do nothing;

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
  unique(request_id, worker_id)
);

-- Indexes for service_requests and job_applications
create index if not exists service_requests_status_idx on public.service_requests(status);
create index if not exists service_requests_user_idx on public.service_requests(user_id);
create index if not exists job_applications_request_idx on public.job_applications(request_id);
create index if not exists job_applications_worker_idx on public.job_applications(worker_id);
create index if not exists job_applications_status_idx on public.job_applications(status);

-- Enable RLS for new tables
alter table public.service_requests enable row level security;
alter table public.job_applications enable row level security;

-- RLS POLICIES FOR SERVICE_REQUESTS
do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='service_requests' and policyname='service_requests_select_open'
  ) then
    create policy service_requests_select_open on public.service_requests
      for select to authenticated
      using (status = 'open' or user_id = auth.uid());
  end if;
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='service_requests' and policyname='service_requests_insert_own'
  ) then
    create policy service_requests_insert_own on public.service_requests
      for insert to authenticated
      with check (user_id = auth.uid());
  end if;
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
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='job_applications' and policyname='job_applications_insert_worker'
  ) then
    create policy job_applications_insert_worker on public.job_applications
      for insert to authenticated
      with check (worker_id = auth.uid());
  end if;
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



