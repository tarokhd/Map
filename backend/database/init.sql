CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS app_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    auth_provider TEXT NOT NULL,
    auth_subject TEXT NOT NULL,
    display_name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (auth_provider, auth_subject)
);

CREATE TABLE IF NOT EXISTS saved_places (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    note TEXT,
    location GEOMETRY(Point, 4326) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS saved_places_user_idx ON saved_places(user_id);
CREATE INDEX IF NOT EXISTS saved_places_location_gix ON saved_places USING GIST(location);

CREATE TABLE IF NOT EXISTS route_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    origin GEOMETRY(Point, 4326) NOT NULL,
    destination GEOMETRY(Point, 4326) NOT NULL,
    route_geometry GEOMETRY(LineString, 4326),
    travel_mode TEXT NOT NULL CHECK (travel_mode IN ('car', 'motorcycle', 'walking')),
    distance_m DOUBLE PRECISION,
    duration_s DOUBLE PRECISION,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS route_history_user_created_idx ON route_history(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS route_history_geometry_gix ON route_history USING GIST(route_geometry);

CREATE TABLE IF NOT EXISTS map_feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES app_users(id) ON DELETE SET NULL,
    category TEXT NOT NULL,
    message TEXT NOT NULL,
    location GEOMETRY(Point, 4326),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS map_feedback_location_gix ON map_feedback USING GIST(location);
