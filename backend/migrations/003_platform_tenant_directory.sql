CREATE FUNCTION platform_tenant_directory(page_size integer, page_offset integer)
RETURNS TABLE(id uuid, slug text, name text, active boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog
AS $$
  SELECT t.id, t.slug::text, t.name::text, t.active FROM public.tenants t
  ORDER BY t.slug LIMIT page_size OFFSET page_offset
$$;

REVOKE ALL ON FUNCTION platform_tenant_directory(integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION platform_tenant_directory(integer, integer) TO bankos_app;
