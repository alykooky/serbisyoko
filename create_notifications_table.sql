-- ============================================================
-- NOTIFICATIONS TABLE
-- Run this in your Supabase SQL Editor
-- ============================================================

-- NOTIFICATIONS TABLE
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.users(id) on delete cascade,
  type text not null, -- 'application_accepted', 'application_rejected', 'booking_created', 'booking_status_changed', 'new_application', etc.
  title text not null,
  message text not null,
  related_id uuid, -- ID of related booking, application, request, etc.
  related_type text, -- 'booking', 'application', 'request', etc.
  is_read boolean default false,
  created_at timestamptz default now()
);

-- Indexes for better performance
create index if not exists notifications_user_idx on public.notifications(user_id);
create index if not exists notifications_user_read_idx on public.notifications(user_id, is_read);
create index if not exists notifications_created_idx on public.notifications(created_at desc);

-- Enable RLS
alter table public.notifications enable row level security;

-- RLS POLICIES FOR NOTIFICATIONS
do $$
begin
  -- Users can view their own notifications
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='notifications' and policyname='notifications_select_own'
  ) then
    create policy notifications_select_own on public.notifications
      for select to authenticated
      using (user_id = auth.uid());
  end if;

  -- Users can update their own notifications (mark as read)
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='notifications' and policyname='notifications_update_own'
  ) then
    create policy notifications_update_own on public.notifications
      for update to authenticated
      using (user_id = auth.uid())
      with check (user_id = auth.uid());
  end if;

  -- System can insert notifications (done via service role or function)
  -- For now, allow authenticated users to insert (we'll use service role in production)
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='notifications' and policyname='notifications_insert_own'
  ) then
    create policy notifications_insert_own on public.notifications
      for insert to authenticated
      with check (user_id = auth.uid());
  end if;

  -- Users can delete their own notifications
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='notifications' and policyname='notifications_delete_own'
  ) then
    create policy notifications_delete_own on public.notifications
      for delete to authenticated
      using (user_id = auth.uid());
  end if;
end$$;

-- Add helpful comment
comment on table public.notifications is 'User notifications for bookings, applications, and system events';


