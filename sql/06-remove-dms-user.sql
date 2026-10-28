DO $cleanup$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dms_reader') THEN
    IF (SELECT shobj_description(oid, 'pg_authid') FROM pg_roles WHERE rolname = 'dms_reader')
       IS DISTINCT FROM 'workshop-dms-utn managed replication role' THEN
      RAISE EXCEPTION 'dms_reader does not belong to this workshop';
    END IF;
    REVOKE SELECT ON ALL TABLES IN SCHEMA tienda FROM dms_reader;
    REVOKE USAGE ON SCHEMA tienda FROM dms_reader;
    EXECUTE format('REVOKE CONNECT ON DATABASE %I FROM dms_reader', current_database());
    REVOKE rds_replication FROM dms_reader;
    -- Fail on unexpected dependencies rather than dropping any owned objects.
    DROP ROLE dms_reader;
  END IF;
END
$cleanup$;
