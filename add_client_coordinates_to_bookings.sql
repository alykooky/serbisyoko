-- ============================================================
-- ADD CLIENT COORDINATES TO BOOKINGS TABLE
-- Run this in your Supabase SQL Editor
-- ============================================================

-- Add client_lat and client_lng columns for storing client location coordinates
alter table public.bookings 
  add column if not exists client_lat double precision;

alter table public.bookings 
  add column if not exists client_lng double precision;

-- Add client_address column for storing full address text
alter table public.bookings 
  add column if not exists client_address text;

-- Add problem_details column for service description
alter table public.bookings 
  add column if not exists problem_details text;

-- Add scheduled_end column for end time
alter table public.bookings 
  add column if not exists scheduled_end timestamptz;

-- Add duration_minutes column
alter table public.bookings 
  add column if not exists duration_minutes integer;

-- Add price column (final agreed price)
alter table public.bookings 
  add column if not exists price integer;

-- Add indexes for better query performance
create index if not exists bookings_client_coords_idx on public.bookings(client_lat, client_lng) 
  where client_lat is not null and client_lng is not null;

-- Add comments
comment on column public.bookings.client_lat is 'Client location latitude for navigation';
comment on column public.bookings.client_lng is 'Client location longitude for navigation';
comment on column public.bookings.client_address is 'Full text address of client location';
comment on column public.bookings.problem_details is 'Description of the service issue/task';
comment on column public.bookings.price is 'Final agreed price for the service';

