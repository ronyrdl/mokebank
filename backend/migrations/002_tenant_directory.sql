CREATE FUNCTION active_tenant_directory(page_size integer, page_offset integer)
RETURNS TABLE(slug text, name text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog
AS $$
  SELECT t.slug::text, t.name::text FROM public.tenants t WHERE t.active
  ORDER BY t.slug LIMIT page_size OFFSET page_offset
$$;

REVOKE ALL ON FUNCTION active_tenant_directory(integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION active_tenant_directory(integer, integer) TO bankos_app;
