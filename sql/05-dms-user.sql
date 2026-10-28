DO $bootstrap$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dms_reader') THEN
    CREATE ROLE dms_reader LOGIN;
    COMMENT ON ROLE dms_reader IS 'workshop-dms-utn managed replication role';
  ELSIF (SELECT shobj_description(oid, 'pg_authid') FROM pg_roles WHERE rolname = 'dms_reader')
        IS DISTINCT FROM 'workshop-dms-utn managed replication role' THEN
    RAISE EXCEPTION 'dms_reader already exists and does not belong to this workshop';
  END IF;
  -- The helper supplies a SCRAM verifier, never a plaintext password, to SQL.
  EXECUTE format('ALTER ROLE dms_reader PASSWORD %L',
                 current_setting('workshop.dms_verifier'));
  GRANT rds_replication TO dms_reader;
  EXECUTE format('GRANT CONNECT ON DATABASE %I TO dms_reader', current_database());
  GRANT USAGE ON SCHEMA tienda TO dms_reader;
  GRANT SELECT ON ALL TABLES IN SCHEMA tienda TO dms_reader;
END
$bootstrap$;
