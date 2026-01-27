-- ============================================================
-- ADD TIME SUGGESTION FEATURE TO BOOKINGS
-- Run this in your Supabase SQL Editor
-- ============================================================

-- Add suggested_time column for worker time suggestions
alter table public.bookings 
  add column if not exists suggested_time timestamptz;

-- Add suggested_by column to track who suggested (worker_id)
alter table public.bookings 
  add column if not exists suggested_by uuid references public.users(id);

-- Add index for better query performance
create index if not exists bookings_suggested_time_idx on public.bookings(suggested_time) 
  where suggested_time is not null;

-- Add comment
comment on column public.bookings.suggested_time is 'Worker suggested alternative time for the booking';
comment on column public.bookings.suggested_by is 'User ID who suggested the time change';


