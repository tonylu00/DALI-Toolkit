-- Initialize DALI-Toolkit database with basic extensions
-- This script is run when the PostgreSQL container starts

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable ltree extension for hierarchical data
CREATE EXTENSION IF NOT EXISTS ltree;

-- Create initial schema (migrations will handle the actual tables)
-- This just ensures extensions are available