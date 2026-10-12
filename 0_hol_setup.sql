-- =============================================================================
-- Cortex Code Control Hub — Hands-on Lab Setup
-- =============================================================================
-- Run each section in order in a Snowsight worksheet.
--
-- PART A: Pre-deployment setup (run BEFORE deploying the Streamlit app)
-- PART B: Post-deployment setup (run AFTER the app is deployed and Phase A
--         "Create Objects" has completed inside the app)
-- =============================================================================


-- =============================================================================
-- PART A: PRE-DEPLOYMENT SETUP
-- =============================================================================
-- Creates the database, schema, and a deployment role so you can upload the
-- Streamlit app. Run this first, then deploy the app via snow streamlit deploy
-- or the Snowsight UI.
-- =============================================================================

-- ── A1. Create the database and schema ──────────────────────────────────────
USE ROLE SYSADMIN;
CREATE DATABASE IF NOT EXISTS CORTEX_CODE_MGMT;
CREATE SCHEMA IF NOT EXISTS CORTEX_CODE_MGMT.APP;

-- ── A2. Create a hub admin role for Streamlit deployment ────────────────────
USE ROLE USERADMIN;
CREATE ROLE IF NOT EXISTS COCO_HUB_ADMIN;
SET MY_USER_ID = CURRENT_USER();
GRANT ROLE COCO_HUB_ADMIN TO USER identifier($MY_USER_ID);

USE ROLE SYSADMIN;
GRANT USAGE ON DATABASE CORTEX_CODE_MGMT TO ROLE COCO_HUB_ADMIN;
GRANT USAGE ON SCHEMA CORTEX_CODE_MGMT.APP TO ROLE COCO_HUB_ADMIN;
GRANT CREATE STREAMLIT ON SCHEMA CORTEX_CODE_MGMT.APP TO ROLE COCO_HUB_ADMIN;
GRANT CREATE STAGE ON SCHEMA CORTEX_CODE_MGMT.APP TO ROLE COCO_HUB_ADMIN;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE COCO_HUB_ADMIN;

-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │  STOP HERE — deploy the Streamlit app, then run Phase A "Create        │
-- │  Objects" inside the app's Setup tab before continuing to Part B.      │
-- └─────────────────────────────────────────────────────────────────────────┘


-- =============================================================================
-- PART B: POST-DEPLOYMENT SETUP
-- =============================================================================
-- Configures Cortex access, credit limits, guardrails, budgets, and grants
-- the app roles to your user. Run after the app's Phase A has created the
-- tables, stored procedures, and tasks.
-- =============================================================================

-- ── B1. Create app roles and grant to your user ─────────────────────────────
-- The prerequisites script creates these roles, but we ensure they exist
-- and are granted to the current user (the app's "Grant Roles to Me" button
-- does not work in Streamlit-in-Snowflake).
USE ROLE USERADMIN;
CREATE ROLE IF NOT EXISTS CC_SP_OWNER_ROLE;
CREATE ROLE IF NOT EXISTS CC_USER_ROLE;
SET MY_USER_ID = CURRENT_USER();
GRANT ROLE CC_SP_OWNER_ROLE TO USER identifier($MY_USER_ID);
GRANT ROLE CC_USER_ROLE TO USER identifier($MY_USER_ID);

-- ── B2. Grant Cortex model access to the SP owner role ──────────────────────
USE ROLE ACCOUNTADMIN;

GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER
  TO ROLE CC_SP_OWNER_ROLE;

-- ── B3. Grant ACCOUNT_USAGE read access to the SP owner role ────────────────
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE
  TO ROLE CC_SP_OWNER_ROLE;

-- ── B4. Grant Cortex model + AI function access to the user role ────────────
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER
  TO ROLE CC_USER_ROLE;

GRANT USE AI FUNCTIONS ON ACCOUNT
  TO ROLE CC_USER_ROLE;

-- ── B5. Set credit limits ───────────────────────────────────────────────────
-- (Optional) Restrict models account-wide, then grant specific models per role:
-- ALTER ACCOUNT SET CORTEX_MODELS_ALLOWLIST = 'None';
-- GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-CLAUDE-SONNET-4-5" TO ROLE CC_USER_ROLE;

-- Account-wide daily limits per surface (rolling 24-hour window, per user)
ALTER ACCOUNT SET CORTEX_CODE_SNOWSIGHT_DAILY_EST_CREDIT_LIMIT_PER_USER = 20;
ALTER ACCOUNT SET CORTEX_CODE_CLI_DAILY_EST_CREDIT_LIMIT_PER_USER = 20;
ALTER ACCOUNT SET CORTEX_CODE_DESKTOP_DAILY_EST_CREDIT_LIMIT_PER_USER = 20;

-- Per-user override (takes precedence over account-level for that user)
ALTER USER identifier($MY_USER_ID) SET CORTEX_CODE_SNOWSIGHT_DAILY_EST_CREDIT_LIMIT_PER_USER = 50;
ALTER USER identifier($MY_USER_ID) SET CORTEX_CODE_CLI_DAILY_EST_CREDIT_LIMIT_PER_USER = 50;
ALTER USER identifier($MY_USER_ID) SET CORTEX_CODE_DESKTOP_DAILY_EST_CREDIT_LIMIT_PER_USER = 50;

-- Remove a per-user override (reverts to account-level)
-- ALTER USER identifier($MY_USER_ID) UNSET CORTEX_CODE_SNOWSIGHT_DAILY_EST_CREDIT_LIMIT_PER_USER;

-- Verify limits
SHOW PARAMETERS LIKE 'CORTEX_CODE%' IN ACCOUNT;
SHOW PARAMETERS LIKE 'CORTEX_CODE%' FOR USER identifier($MY_USER_ID);

-- ── B6. Enable Cortex AI Guardrails ─────────────────────────────────────────
ALTER ACCOUNT SET AI_SETTINGS = $$
  guardrails:
    advanced_prompt_injection:
      - enabled: true
$$;

-- Verify
SHOW PARAMETERS LIKE 'AI_SETTINGS' IN ACCOUNT;

-- To disable if needed:
-- ALTER ACCOUNT UNSET AI_SETTINGS;

-- ── B7. Cost tagging and budgets ────────────────────────────────────────────
USE ROLE SYSADMIN;
CREATE SCHEMA IF NOT EXISTS CORTEX_CODE_MGMT.TAGS;
CREATE SCHEMA IF NOT EXISTS CORTEX_CODE_MGMT.BUDGETS;

GRANT USAGE ON SCHEMA CORTEX_CODE_MGMT.TAGS TO ROLE COCO_HUB_ADMIN;
GRANT USAGE ON SCHEMA CORTEX_CODE_MGMT.BUDGETS TO ROLE COCO_HUB_ADMIN;

-- Tag an agent, create a budget, set limit, notify at 80%
USE ROLE ACCOUNTADMIN;
CREATE TAG IF NOT EXISTS CORTEX_CODE_MGMT.TAGS.COST_CENTER ALLOWED_VALUES 'cortex-code-agent';
ALTER AGENT IF EXISTS health_insurance_agent SET TAG CORTEX_CODE_MGMT.TAGS.COST_CENTER = 'cortex-code-agent';

USE SCHEMA CORTEX_CODE_MGMT.BUDGETS;
CREATE SNOWFLAKE.CORE.BUDGET IF NOT EXISTS ai_agent_budget();
CALL ai_agent_budget!SET_SPENDING_LIMIT(1000);  -- monthly credit cap
CALL ai_agent_budget!SET_NOTIFICATION_THRESHOLD(80);
-- Full setup with revoke-at-100% SP:
-- https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-resource-budgets

-- ── B8. Grant app roles to your user ────────────────────────────────────────
-- These roles are created by the prerequisites script (Phase A).
-- The app's "Grant Roles to Me" button fails in Streamlit-in-Snowflake,
-- so grant them manually here.
GRANT ROLE CC_ADMIN_ROLE TO USER identifier($MY_USER_ID);
GRANT ROLE CC_USER_ROLE TO USER identifier($MY_USER_ID);
