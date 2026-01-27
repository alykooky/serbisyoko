-- ============================================================
-- SERVICE SUBCATEGORIES TABLE
-- Run this in your Supabase SQL Editor
-- ============================================================

-- Create service_subcategories table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.service_subcategories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_name text NOT NULL, -- e.g., 'Plumber', 'Electrician'
  title text NOT NULL, -- e.g., 'Maintenance', 'Installation'
  default_price double precision, -- Optional default pricing suggestion
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(service_name, title) -- Prevent duplicate subcategories per service
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS service_subcategories_service_name_idx 
  ON public.service_subcategories(service_name);
CREATE INDEX IF NOT EXISTS service_subcategories_title_idx 
  ON public.service_subcategories(title);

-- Enable RLS
ALTER TABLE public.service_subcategories ENABLE ROW LEVEL SECURITY;

-- RLS Policies: Everyone can view subcategories, only admins can modify
CREATE POLICY service_subcategories_select 
ON public.service_subcategories
FOR SELECT 
TO authenticated
USING (true); -- Everyone can read subcategories

CREATE POLICY service_subcategories_insert_admin 
ON public.service_subcategories
FOR INSERT 
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.users 
    WHERE id = auth.uid() 
    AND role = 'Admin'
  )
);

CREATE POLICY service_subcategories_update_admin 
ON public.service_subcategories
FOR UPDATE 
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.users 
    WHERE id = auth.uid() 
    AND role = 'Admin'
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.users 
    WHERE id = auth.uid() 
    AND role = 'Admin'
  )
);

CREATE POLICY service_subcategories_delete_admin 
ON public.service_subcategories
FOR DELETE 
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.users 
    WHERE id = auth.uid() 
    AND role = 'Admin'
  )
);

-- Add comment
COMMENT ON TABLE public.service_subcategories IS 'Subcategories for services with optional default pricing suggestions';

