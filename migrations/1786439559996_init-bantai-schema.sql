-- Up Migration

CREATE EXTENSION IF NOT EXISTS postgis;

-- 1. ENUMS
CREATE TYPE user_role AS ENUM ('driver', 'responder', 'admin', 'super');
CREATE TYPE cc_type AS ENUM ('barangay', 'police_station', 'mdrrmo');
CREATE TYPE agency_type AS ENUM ('police', 'barangay_tanod', 'mdrrmo');
CREATE TYPE alert_status AS ENUM ('pending', 'viewing', 'dispatched', 'arrived', 'resolved');
CREATE TYPE alert_type AS ENUM ('threat_blade', 'threat_gun', 'threat_human', 'accident');
CREATE TYPE service_provider AS ENUM ('angkas', 'move_it', 'joyride', 'independent');
CREATE TYPE availability_status AS ENUM ('on_duty', 'off_duty', 'dispatched', 'transit');
CREATE TYPE blood_type_enum AS ENUM ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'unknown');
CREATE TYPE police_rank AS ENUM (
    'PGEN', 'PLTGEN', 'PMGEN', 'PBGEN', 'PCOL', 'PLTCOL',
    'PMAJ', 'PCPT', 'PLT', 'PEMS', 'PCMS', 'PSMS',
    'PMSg', 'PSSg', 'PCpl', 'Pat', 'none'
);
CREATE TYPE device_status AS ENUM ('inventory', 'paired', 'reported_lost', 'decommissioned');
CREATE TYPE audit_action AS ENUM (
    'CREATE_CC', 'CREATE_USER', 'UPDATE_USER', 'CHANGE_ROLE',
    'REGISTER_DEVICE', 'PAIR_DEVICE', 'UNPAIR_DEVICE',
    'ACKNOWLEDGE_ALERT', 'DISPATCH_RESPONDER', 'RESOLVE_ALERT',
    'AUTH_LOGIN', 'AUTH_LOGOUT', 'AUTH_REVOKE_SESSION'
);
CREATE TYPE auth_provider_enum AS ENUM ('local', 'google', 'apple');
CREATE TYPE report_status AS ENUM ('draft', 'submitted', 'under_review', 'approved');
CREATE TYPE arrival_confirmation_method AS ENUM ('gps', 'manual');

-- 2. CORE TABLES
CREATE TABLE IF NOT EXISTS command_center (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(150) NOT NULL UNIQUE,
    type cc_type NOT NULL,
    branch VARCHAR(100) NOT NULL,
    location GEOGRAPHY(Point, 4326) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chck_cc_name_not_empty CHECK (trim(name) <> '')
);

CREATE TABLE IF NOT EXISTS user_account (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    f_name VARCHAR(50) NOT NULL,
    l_name VARCHAR(50) NOT NULL,
    m_name VARCHAR(50),
    email VARCHAR(150) NOT NULL UNIQUE,
    m_number VARCHAR(15),
    role user_role NOT NULL,
    -- RESTRICT: a command_center with active admin/responder staff cannot be
    -- deleted outright; staff must be reassigned/deactivated first. This is
    -- required to stay compatible with branch_scope_check below (SET NULL
    -- would attempt to null this column for admin/responder rows, which
    -- branch_scope_check forbids, causing the same failure less explicitly).
    command_center_id UUID REFERENCES command_center(id) ON DELETE RESTRICT,

    -- Identity & Auth
    avatar_url TEXT,
    auth_provider auth_provider_enum NOT NULL DEFAULT 'local',
    provider_id VARCHAR(255),
    password_hash VARCHAR(255),

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ DEFAULT NULL,

    CONSTRAINT branch_scope_check CHECK (
        (role IN ('admin', 'responder') AND command_center_id IS NOT NULL)
        OR (role IN ('driver', 'super') AND command_center_id IS NULL)
    ),
    CONSTRAINT chck_m_number_format CHECK (m_number IS NULL OR m_number ~ '^\+639\d{9}$'),
    CONSTRAINT chck_f_name_format CHECK (f_name ~ '^[[:alpha:]\s\-]+$'),
    CONSTRAINT chck_l_name_format CHECK (l_name ~ '^[[:alpha:]\s\-]+$'),
    CONSTRAINT chck_m_name_format CHECK (m_name IS NULL OR m_name ~ '^[[:alpha:]\s\-]+$'),
    CONSTRAINT chck_auth_requirements CHECK (
        -- admin/responder/super: provisioned internally, local auth only,
        -- never SSO. Registration for these roles is never public.
        (role IN ('admin', 'responder', 'super')
            AND auth_provider = 'local'
            AND password_hash IS NOT NULL
            AND provider_id IS NULL)
        OR
        -- driver: auth_provider reflects the account's current/primary
        -- method and must have its matching credential populated. A
        -- second credential (e.g. a password added after SSO signup) may
        -- also be present, but auth_provider itself must always line up
        -- with a real, non-null value for that method.
        (role = 'driver'
            AND (
                (auth_provider = 'local' AND password_hash IS NOT NULL)
                OR (auth_provider IN ('google', 'apple') AND provider_id IS NOT NULL)
            ))
    )
);

-- 3. PROFILE EXTENSIONS
CREATE TABLE IF NOT EXISTS d_profile (
    user_id UUID PRIMARY KEY REFERENCES user_account(id) ON DELETE CASCADE,
    service_provider service_provider NOT NULL DEFAULT 'independent',
    service_id VARCHAR(50),
    plate_number VARCHAR(20),
    blood_type blood_type_enum NOT NULL DEFAULT 'unknown',
    emergency_contacts JSONB NOT NULL DEFAULT '[]'::jsonb,

    CONSTRAINT service_id_requires_provider CHECK (
        (service_provider = 'independent' AND service_id IS NULL)
        OR (service_provider != 'independent' AND service_id IS NOT NULL)
    ),
    CONSTRAINT emergency_contacts_is_array CHECK (jsonb_typeof(emergency_contacts) = 'array'),
    CONSTRAINT emergency_contacts_max_three CHECK (jsonb_array_length(emergency_contacts) <= 3)
);

CREATE TABLE IF NOT EXISTS r_profile (
    user_id UUID PRIMARY KEY REFERENCES user_account(id) ON DELETE CASCADE,
    agency agency_type NOT NULL,
    call_sign VARCHAR(50),
    rank police_rank NOT NULL DEFAULT 'none',
    availability availability_status NOT NULL DEFAULT 'off_duty',

    -- Real-time Dispatch Requirements
    last_active_at TIMESTAMPTZ DEFAULT now(),
    last_known_location GEOGRAPHY(Point, 4326),

    CONSTRAINT chck_agency_requirements CHECK (
        (agency = 'police' AND call_sign IS NOT NULL AND rank != 'none') OR
        (agency = 'barangay_tanod') OR
        (agency = 'mdrrmo' AND call_sign IS NOT NULL)
    )
);

-- 4. HARDWARE MANAGEMENT
CREATE TABLE IF NOT EXISTS device (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hardware_serial VARCHAR(100) NOT NULL UNIQUE,
    status device_status NOT NULL DEFAULT 'inventory',
    driver_id UUID REFERENCES user_account(id) ON DELETE SET NULL,
    registered_by UUID REFERENCES user_account(id) ON DELETE SET NULL,
    registered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    paired_at TIMESTAMPTZ,
    unpaired_at TIMESTAMPTZ,

    CONSTRAINT chck_device_pairing CHECK (
        (status = 'paired' AND driver_id IS NOT NULL AND paired_at IS NOT NULL AND unpaired_at IS NULL) OR
        (status IN ('inventory', 'decommissioned') AND driver_id IS NULL AND paired_at IS NULL) OR
        (status = 'reported_lost')
    )
);

-- 5. STATEFUL AUTHENTICATION & SESSION MANAGEMENT
CREATE TABLE IF NOT EXISTS user_session (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES user_account(id) ON DELETE CASCADE,
    device_id UUID REFERENCES device(id) ON DELETE SET NULL,
    refresh_token_hash VARCHAR(255) NOT NULL,
    ip_address VARCHAR(45),
    user_agent TEXT,
    is_revoked BOOLEAN NOT NULL DEFAULT false,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chck_expires_future CHECK (expires_at > created_at)
);

-- 6. INCIDENT & RESPONSE
CREATE TABLE IF NOT EXISTS alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id UUID NOT NULL REFERENCES user_account(id) ON DELETE CASCADE,
    device_id UUID REFERENCES device(id) ON DELETE SET NULL,
    location GEOGRAPHY(Point, 4326) NOT NULL,
    alert_type alert_type NOT NULL,
    confidence_level NUMERIC(5,2) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT con_level_validation CHECK (confidence_level >= 0 AND confidence_level <= 100)
);

CREATE TABLE IF NOT EXISTS alert_branch_response (
    alert_id UUID NOT NULL REFERENCES alerts(id) ON DELETE CASCADE,
    command_center_id UUID NOT NULL REFERENCES command_center(id) ON DELETE CASCADE,
    status alert_status NOT NULL DEFAULT 'pending',
    assigned_responder_id UUID REFERENCES user_account(id) ON DELETE SET NULL,

    -- who confirmed arrival, and how (restores the GPS-vs-manual fallback
    -- distinction from the original design)
    arrived_confirmed_by UUID REFERENCES user_account(id) ON DELETE SET NULL,
    arrival_confirmation_method arrival_confirmation_method,

    triggered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    acknowledged_at TIMESTAMPTZ,
    dispatched_at TIMESTAMPTZ,
    arrived_at TIMESTAMPTZ,
    resolved_at TIMESTAMPTZ,

    PRIMARY KEY (alert_id, command_center_id),

    CONSTRAINT chck_arrival_confirmation_consistency CHECK (
        (arrived_at IS NULL AND arrival_confirmation_method IS NULL)
        OR (arrived_at IS NOT NULL AND arrival_confirmation_method IS NOT NULL)
    )
);

-- 7. POST-INCIDENT REPORTING
CREATE TABLE IF NOT EXISTS incident_report (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    alert_id UUID NOT NULL REFERENCES alerts(id) ON DELETE CASCADE,
    command_center_id UUID NOT NULL REFERENCES command_center(id) ON DELETE CASCADE,

    assigned_reporter_id UUID REFERENCES user_account(id) ON DELETE SET NULL,
    submitted_by_id UUID REFERENCES user_account(id) ON DELETE SET NULL,

    summary TEXT NOT NULL,
    detailed_narrative TEXT,
    evidence_urls JSONB NOT NULL DEFAULT '[]'::jsonb,
    status report_status NOT NULL DEFAULT 'draft',

    submitted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chck_evidence_urls_array CHECK (jsonb_typeof(evidence_urls) = 'array')
);

-- 8. SYSTEM AUDIT LOGGING
CREATE TABLE IF NOT EXISTS system_audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id UUID REFERENCES user_account(id) ON DELETE SET NULL,
    command_center_id UUID REFERENCES command_center(id) ON DELETE SET NULL,
    action audit_action NOT NULL,
    target_entity VARCHAR(50) NOT NULL,
    target_id UUID NOT NULL,
    old_payload JSONB,
    new_payload JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 9. DASHBOARD VIEWS
CREATE OR REPLACE VIEW branch_incident_logs AS
SELECT
    a.id AS alert_id,
    abr.command_center_id,
    a.alert_type,
    a.confidence_level,
    abr.status,
    u.f_name || ' ' || u.l_name ||
        CASE WHEN u.deleted_at IS NOT NULL THEN ' (Account Deleted)' ELSE '' END AS rider_name,
    d.hardware_serial,
    CASE
        WHEN abr.assigned_responder_id IS NULL THEN 'Unassigned'
        WHEN r.deleted_at IS NOT NULL THEN r.f_name || ' ' || r.l_name || ' (Inactive)'
        ELSE r.f_name || ' ' || r.l_name
    END AS dispatched_responder_name,
    abr.triggered_at,
    abr.acknowledged_at,
    abr.arrived_at,
    abr.resolved_at,
    EXTRACT(EPOCH FROM (abr.acknowledged_at - abr.triggered_at)) AS reaction_time_seconds
FROM alerts a
JOIN alert_branch_response abr ON a.id = abr.alert_id
JOIN user_account u ON a.driver_id = u.id
LEFT JOIN device d ON a.device_id = d.id
LEFT JOIN user_account r ON abr.assigned_responder_id = r.id;

-- 10. DIAGNOSTIC VIEWS
CREATE OR REPLACE VIEW v_index_performance AS
SELECT
    sui.schemaname,
    sui.relname AS table_name,
    sui.indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(sui.indexrelid)) AS index_size,
    sui.idx_scan AS total_index_scans,
    sui.idx_tup_read AS tuples_read_from_index,
    sui.idx_tup_fetch AS tuples_fetched_from_table,
    (sut.n_tup_ins + sut.n_tup_upd + sut.n_tup_del) AS total_table_writes,
    CASE
        WHEN i.indisprimary THEN 'PRIMARY_KEY'
        WHEN i.indisunique THEN 'UNIQUE_CONSTRAINT'
        WHEN sui.idx_scan = 0 THEN 'UNUSED'
        WHEN (sut.n_tup_ins + sut.n_tup_upd + sut.n_tup_del) > 1000
             AND sui.idx_scan < 50 THEN 'HIGH_WRITE_LOW_READ'
        ELSE 'ACTIVE'
    END AS assessment_code
FROM pg_stat_user_indexes sui
JOIN pg_stat_user_tables sut ON sui.relid = sut.relid
JOIN pg_index i ON sui.indexrelid = i.indexrelid;

CREATE OR REPLACE VIEW v_table_index_usage AS
SELECT
    relname AS table_name,
    seq_scan AS sequential_scans,
    idx_scan AS index_scans,
    n_tup_ins + n_tup_upd + n_tup_del AS total_writes,
    ROUND(
        100.0 * idx_scan / NULLIF(seq_scan + idx_scan, 0), 2
    ) AS index_usage_percentage
FROM pg_stat_user_tables;

-- 11. PERFORMANCE INDEXES
CREATE INDEX idx_command_center_location ON command_center USING GIST (location);
CREATE INDEX idx_alerts_location ON alerts USING GIST (location);

CREATE INDEX idx_user_account_cc_id ON user_account(command_center_id);
CREATE INDEX idx_device_driver_id ON device(driver_id);
CREATE INDEX idx_device_hardware_serial ON device(hardware_serial);
CREATE INDEX idx_alerts_driver_id ON alerts(driver_id);
CREATE INDEX idx_abr_assigned_responder ON alert_branch_response(assigned_responder_id);

-- Added: composite PK on alert_branch_response is ordered (alert_id, cc_id),
-- which doesn't efficiently serve "all alerts for my branch" lookups.
CREATE INDEX idx_abr_command_center ON alert_branch_response(command_center_id);

CREATE INDEX idx_audit_cc_id ON system_audit_log(command_center_id);
CREATE INDEX idx_audit_created_at ON system_audit_log(created_at);

-- Session Indexes
CREATE INDEX idx_user_session_token ON user_session(refresh_token_hash);
CREATE INDEX idx_user_session_user_id ON user_session(user_id) WHERE is_revoked = false;
CREATE INDEX idx_user_session_expires_at ON user_session(expires_at);

-- Dispatch & Heartbeat Indexes
CREATE INDEX idx_r_profile_location ON r_profile USING GIST (last_known_location);
CREATE INDEX idx_r_profile_availability ON r_profile(availability, last_active_at);

-- Soft Delete Index
CREATE INDEX idx_user_account_deleted_at ON user_account(deleted_at) WHERE deleted_at IS NULL;

-- Post-incident Report Indexes
CREATE INDEX idx_incident_report_alert ON incident_report(alert_id);
CREATE INDEX idx_incident_report_cc ON incident_report(command_center_id);
CREATE INDEX idx_incident_report_assignee ON incident_report(assigned_reporter_id);


-- Down Migration

DROP VIEW IF EXISTS v_table_index_usage;
DROP VIEW IF EXISTS v_index_performance;
DROP VIEW IF EXISTS branch_incident_logs;

DROP TABLE IF EXISTS system_audit_log;
DROP TABLE IF EXISTS incident_report;
DROP TABLE IF EXISTS alert_branch_response;
DROP TABLE IF EXISTS alerts;
DROP TABLE IF EXISTS user_session;
DROP TABLE IF EXISTS device;
DROP TABLE IF EXISTS r_profile;
DROP TABLE IF EXISTS d_profile;
DROP TABLE IF EXISTS user_account;
DROP TABLE IF EXISTS command_center;

DROP TYPE IF EXISTS arrival_confirmation_method;
DROP TYPE IF EXISTS report_status;
DROP TYPE IF EXISTS auth_provider_enum;
DROP TYPE IF EXISTS audit_action;
DROP TYPE IF EXISTS device_status;
DROP TYPE IF EXISTS police_rank;
DROP TYPE IF EXISTS blood_type_enum;
DROP TYPE IF EXISTS service_provider;
DROP TYPE IF EXISTS alert_type;
DROP TYPE IF EXISTS alert_status;
DROP TYPE IF EXISTS agency_type;
DROP TYPE IF EXISTS cc_type;
DROP TYPE IF EXISTS user_role;
DROP TYPE IF EXISTS availability_status;