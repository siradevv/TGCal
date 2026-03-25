-- 005: Add return flight columns to swap_listings for round-trip swaps
-- Thai Airways crew always fly outbound + return, so swaps include both legs.

ALTER TABLE public.swap_listings
  ADD COLUMN return_flight_code   TEXT,
  ADD COLUMN return_origin        TEXT,
  ADD COLUMN return_destination   TEXT,
  ADD COLUMN return_flight_date   DATE,
  ADD COLUMN return_departure_time TEXT;

-- Index for filtering by return date
CREATE INDEX idx_swap_listings_return_flight_date
  ON public.swap_listings (return_flight_date)
  WHERE return_flight_date IS NOT NULL;

-- Text length constraints (matching existing columns from migration 004)
ALTER TABLE public.swap_listings
  ADD CONSTRAINT chk_return_flight_code_len CHECK (length(return_flight_code) <= 20),
  ADD CONSTRAINT chk_return_origin_len      CHECK (length(return_origin) <= 10),
  ADD CONSTRAINT chk_return_destination_len CHECK (length(return_destination) <= 10),
  ADD CONSTRAINT chk_return_departure_time_len CHECK (length(return_departure_time) <= 10);
