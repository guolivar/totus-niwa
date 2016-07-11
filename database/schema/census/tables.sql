SET search_path = census, public;

-- Administrative hierarchy
--
--           RC       Regional Council
--          /  \
--         TA  TA     Territorial Authority
--        /  \
--       WA  WA       Ward
--      /  \
--     AU  AU         Area Unit
--    /  \
--   MB  MB           Meshblock
--
CREATE TABLE admin_type (
  id          SERIAL,
  code        CHARACTER(2) NOT NULL,
  description TEXT         NOT NULL
);

COMMENT ON TABLE admin_type IS 'Administrative types or levels in area hierarchy';

CREATE TABLE admin_area (
  id                SERIAL,
  parent_id         INTEGER,
  admin_type_id     INTEGER     NOT NULL,
  census_identifier VARCHAR(32) NOT NULL,
  description       TEXT        NOT NULL,
  geom              GEOMETRY (MULTIPOLYGON, 4326)
);

COMMENT ON TABLE admin_area IS 'An administrative area in the area hierarchy';


-- Census information hierarchy
--
--         TOPIC             About People
--        /     \
--   CATEGORY  CATEGORY      Age in 5 year groups
--    /   \
-- CLASS CLASS               0 - 4 years, 5 - 9 years
--
CREATE TABLE topic (
  id          SERIAL,
  code        VARCHAR(32) NOT NULL,
  description TEXT        NOT NULL
);

COMMENT ON TABLE topic IS 'Census topics, eg. about people, households, etc.';

CREATE TABLE category (
  id          SERIAL,
  topic_id    INTEGER     NOT NULL,
  code        VARCHAR(32) NOT NULL,
  description TEXT        NOT NULL
);

COMMENT ON TABLE category IS 'Category for a Census topic, eg. Age in 5 year groups';

CREATE TABLE class (
  id          SERIAL,
  category_id INTEGER     NOT NULL,
  code        VARCHAR(32) NOT NULL,
  description TEXT        NOT NULL
);

COMMENT ON TABLE class IS 'The classes of a topic category, eg. 0 - 4 years';

CREATE TABLE demographic (
  id            SERIAL,
  admin_area_id INTEGER NOT NULL,
  class_id      INTEGER NOT NULL,
  count         INTEGER NOT NULL,
  year          SMALLINT NOT NULL
);

COMMENT ON TABLE demographic IS 'The instance of a statistic of the human population';
