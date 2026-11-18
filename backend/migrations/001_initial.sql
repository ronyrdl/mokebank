CREATE TABLE tenants (
  id uuid PRIMARY KEY,
  slug varchar(63) NOT NULL UNIQUE,
  name varchar(120) NOT NULL,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE tenant_config (
  tenant_id uuid PRIMARY KEY REFERENCES tenants(id),
  currency char(3) NOT NULL CHECK (currency IN ('COP','USD','EUR')),
  transaction_limit numeric(20,2) NOT NULL CHECK (transaction_limit > 0),
  fee_fixed numeric(20,2) NOT NULL CHECK (fee_fixed >= 0),
  fee_percent numeric(7,4) NOT NULL CHECK (fee_percent BETWEEN 0 AND 100)
);

CREATE TABLE users (
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  id uuid NOT NULL,
  first_name varchar(80) NOT NULL,
  last_name varchar(80) NOT NULL,
  email varchar(254) NOT NULL,
  password_hash text NOT NULL,
  role text NOT NULL CHECK (role IN ('ADMIN','CLIENT')),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id,id),
  UNIQUE (tenant_id,email)
);

CREATE TABLE accounts (
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  id uuid NOT NULL,
  number varchar(32) NOT NULL,
  owner_id uuid NOT NULL,
  currency char(3) NOT NULL CHECK (currency IN ('COP','USD','EUR')),
  balance numeric(20,2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE','BLOCKED')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id,id),
  UNIQUE (tenant_id,number),
  FOREIGN KEY (tenant_id,owner_id) REFERENCES users(tenant_id,id)
);
CREATE INDEX accounts_owner_idx ON accounts (tenant_id,owner_id,created_at DESC,id);

CREATE TABLE exchange_rates (
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  source_currency char(3) NOT NULL CHECK (source_currency IN ('COP','USD','EUR')),
  destination_currency char(3) NOT NULL CHECK (destination_currency IN ('COP','USD','EUR')),
  rate numeric(24,10) NOT NULL CHECK (rate > 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id,source_currency,destination_currency),
  CHECK (source_currency <> destination_currency)
);

CREATE TABLE transactions (
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  id uuid NOT NULL,
  user_id uuid NOT NULL,
  type text NOT NULL CHECK (type IN ('DEPOSIT','WITHDRAW','TRANSFER')),
  source_account_id uuid,
  destination_account_id uuid,
  original_amount numeric(20,2) NOT NULL CHECK (original_amount > 0),
  converted_amount numeric(20,2) CHECK (converted_amount > 0),
  source_currency char(3),
  destination_currency char(3),
  exchange_rate numeric(24,10) CHECK (exchange_rate > 0),
  fee numeric(20,2) NOT NULL CHECK (fee >= 0),
  status text NOT NULL CHECK (status IN ('PENDING','COMPLETED','FAILED')),
  description varchar(255),
  failure_code varchar(80),
  idempotency_key uuid NOT NULL,
  correlation_id varchar(128) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id,id),
  FOREIGN KEY (tenant_id,user_id) REFERENCES users(tenant_id,id),
  FOREIGN KEY (tenant_id,source_account_id) REFERENCES accounts(tenant_id,id),
  FOREIGN KEY (tenant_id,destination_account_id) REFERENCES accounts(tenant_id,id),
  CHECK (status <> 'COMPLETED' OR (
    converted_amount IS NOT NULL AND exchange_rate IS NOT NULL
    AND source_currency IS NOT NULL AND destination_currency IS NOT NULL
    AND ((type='DEPOSIT' AND source_account_id IS NULL AND destination_account_id IS NOT NULL)
      OR (type='WITHDRAW' AND source_account_id IS NOT NULL AND destination_account_id IS NULL)
      OR (type='TRANSFER' AND source_account_id IS NOT NULL AND destination_account_id IS NOT NULL
        AND source_account_id <> destination_account_id))
  ))
);
CREATE INDEX transactions_history_idx ON transactions (tenant_id,created_at DESC,id);
CREATE INDEX transactions_source_idx ON transactions (tenant_id,source_account_id,created_at DESC,id);
CREATE INDEX transactions_destination_idx ON transactions (tenant_id,destination_account_id,created_at DESC,id);
CREATE INDEX transactions_actor_idx ON transactions (tenant_id,user_id,created_at DESC,id);

CREATE TABLE idempotency_records (
  tenant_id uuid NOT NULL,
  user_id uuid NOT NULL,
  key uuid NOT NULL,
  fingerprint char(64) NOT NULL,
  status text NOT NULL CHECK (status IN ('PROCESSING','COMPLETED')),
  http_status smallint,
  response_body text,
  expires_at timestamptz NOT NULL,
  PRIMARY KEY (tenant_id,user_id,key),
  FOREIGN KEY (tenant_id,user_id) REFERENCES users(tenant_id,id),
  CHECK ((status='PROCESSING' AND response_body IS NULL AND http_status IS NULL)
      OR (status='COMPLETED' AND response_body IS NOT NULL AND http_status BETWEEN 100 AND 599))
);
CREATE INDEX idempotency_expiry_idx ON idempotency_records (tenant_id,expires_at);

CREATE TABLE audit_logs (
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  action varchar(80) NOT NULL,
  resource varchar(120) NOT NULL,
  previous_state jsonb,
  new_state jsonb,
  ip varchar(64) NOT NULL,
  correlation_id varchar(128) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id,id),
  FOREIGN KEY (tenant_id,user_id) REFERENCES users(tenant_id,id)
);
CREATE INDEX audit_history_idx ON audit_logs (tenant_id,created_at DESC,id);

CREATE TABLE webhook_config (
  tenant_id uuid PRIMARY KEY REFERENCES tenants(id),
  url text NOT NULL,
  secret text NOT NULL,
  active boolean NOT NULL DEFAULT true,
  timeout_ms integer NOT NULL CHECK (timeout_ms BETWEEN 500 AND 15000)
);

CREATE TABLE outbox_events (
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  id uuid NOT NULL,
  type text NOT NULL,
  payload jsonb NOT NULL,
  correlation_id varchar(128) NOT NULL,
  webhook_url text,
  webhook_secret text,
  timeout_ms integer,
  state text NOT NULL DEFAULT 'PENDING' CHECK (state IN ('PENDING','DELIVERED','FAILED','SKIPPED')),
  attempts integer NOT NULL DEFAULT 0,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  lease_token uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id,id)
);
CREATE INDEX outbox_queue_idx ON outbox_events (tenant_id,next_attempt_at,id) WHERE state='PENDING';

CREATE TABLE webhook_deliveries (
  tenant_id uuid NOT NULL,
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL,
  attempt integer NOT NULL,
  http_status integer,
  error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id,id),
  UNIQUE (tenant_id,event_id,attempt),
  FOREIGN KEY (tenant_id,event_id) REFERENCES outbox_events(tenant_id,id)
);

CREATE TABLE refresh_tokens (
  tenant_id uuid NOT NULL,
  id uuid NOT NULL,
  user_id uuid NOT NULL,
  token_hash char(64) NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  PRIMARY KEY (tenant_id,id),
  FOREIGN KEY (tenant_id,user_id) REFERENCES users(tenant_id,id)
);
CREATE INDEX refresh_user_idx ON refresh_tokens (tenant_id,user_id);

CREATE FUNCTION current_tenant() RETURNS uuid LANGUAGE sql STABLE
AS $$ SELECT nullif(current_setting('bankos.tenant_id',true),'')::uuid $$;

DO $$
DECLARE tbl text;
DECLARE scope_column text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['tenants','tenant_config','users','accounts','exchange_rates','transactions',
      'idempotency_records','audit_logs','webhook_config','outbox_events','webhook_deliveries','refresh_tokens'] LOOP
    scope_column := CASE WHEN tbl='tenants' THEN 'id' ELSE 'tenant_id' END;
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',tbl);
    EXECUTE format('ALTER TABLE public.%I FORCE ROW LEVEL SECURITY',tbl);
    EXECUTE format('CREATE POLICY tenant_isolation ON public.%I USING (%I = public.current_tenant()) WITH CHECK (%I = public.current_tenant())',
      tbl,scope_column,scope_column);
  END LOOP;
END
$$;

CREATE FUNCTION lookup_tenant(requested_slug text) RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog
AS $$ SELECT id FROM public.tenants WHERE slug=requested_slug AND active $$;

CREATE FUNCTION outbox_tenants() RETURNS SETOF uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog
AS $$ SELECT DISTINCT tenant_id FROM public.outbox_events WHERE state='PENDING' AND next_attempt_at <= now() $$;

CREATE FUNCTION reject_immutable_change() RETURNS trigger LANGUAGE plpgsql
AS $$ BEGIN RAISE EXCEPTION 'Immutable record'; END $$;

CREATE TRIGGER immutable_audit BEFORE UPDATE OR DELETE ON audit_logs
FOR EACH ROW EXECUTE FUNCTION reject_immutable_change();
CREATE TRIGGER immutable_transaction BEFORE UPDATE OR DELETE ON transactions
FOR EACH ROW EXECUTE FUNCTION reject_immutable_change();

REVOKE ALL ON FUNCTION lookup_tenant(text), outbox_tenants() FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO bankos_app;
GRANT SELECT,INSERT,UPDATE ON tenants,tenant_config,users,accounts,exchange_rates,webhook_config,outbox_events,refresh_tokens TO bankos_app;
GRANT SELECT,INSERT ON transactions,audit_logs,webhook_deliveries TO bankos_app;
GRANT SELECT,INSERT,UPDATE,DELETE ON idempotency_records TO bankos_app;
GRANT EXECUTE ON FUNCTION lookup_tenant(text),outbox_tenants() TO bankos_app;
