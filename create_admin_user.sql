-- Create Admin User Script for SerbisyoKo
-- Run this in Supabase SQL Editor to create an admin user

-- First, create the admin user in auth.users (this needs to be done through Supabase Auth UI)
-- Then run this script to add the admin role to the users table

-- Insert admin user into public.users table
-- Replace 'YOUR_ADMIN_USER_ID' with the actual UUID from auth.users
INSERT INTO public.users (id, email, name, role, created_at)
VALUES (
  'YOUR_ADMIN_USER_ID', -- Replace with actual UUID from auth.users
  'admin@serbisyoko.com',
  'Admin User',
  'Admin',
  NOW()
)
ON CONFLICT (id) DO UPDATE SET
  role = 'Admin',
  updated_at = NOW();

-- Create a worker profile for the admin (optional, for testing)
INSERT INTO public.worker_profiles (user_id, about, hourly_rate, is_verified, verification_status, service_area, availability_status, documents, updated_at)
VALUES (
  'YOUR_ADMIN_USER_ID', -- Replace with actual UUID from auth.users
  'Platform Administrator',
  0,
  true,
  'approved',
  'Davao City',
  'OFF',
  '[]'::jsonb,
  NOW()
)
ON CONFLICT (user_id) DO UPDATE SET
  is_verified = true,
  verification_status = 'approved',
  updated_at = NOW();

-- Instructions for creating admin user:
-- 1. Go to Supabase Dashboard > Authentication > Users
-- 2. Click "Add user" and create a user with email: admin@serbisyoko.com
-- 3. Copy the user ID from the created user
-- 4. Replace 'YOUR_ADMIN_USER_ID' in this script with the actual UUID
-- 5. Run this script in Supabase SQL Editor



