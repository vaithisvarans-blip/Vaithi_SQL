WITH loanx_id_cte AS (
    SELECT 
        weighted_average_all_in_rate,
        loanx_id,
        SECURITY_ID,
        CUSIP_ID,
        business_date,
        lead_manager,
        deal_sponsor
    FROM PROD_STAGING.PUBLIC.WSO_DAILY_SECURITYMASTER_ENRICHMENT
    WHERE COALESCE(loanx_id,'') <> ''
),

security_id_cte AS (
    SELECT 
        weighted_average_all_in_rate,
        loanx_id,
        SECURITY_ID,
        CUSIP_ID,
        business_date,
        lead_manager,
        deal_sponsor
    FROM PROD_STAGING.PUBLIC.WSO_DAILY_SECURITYMASTER_ENRICHMENT
    WHERE COALESCE(SECURITY_ID,'') <> ''
),

cusip_id_cte AS (
    SELECT 
        weighted_average_all_in_rate,
        loanx_id,
        SECURITY_ID,
        CUSIP_ID,
        business_date,
        lead_manager,
        deal_sponsor
    FROM PROD_STAGING.PUBLIC.WSO_DAILY_SECURITYMASTER_ENRICHMENT
    WHERE COALESCE(CUSIP_ID,'') <> ''
),

loanx_result AS (
    SELECT 
        a.weighted_average_all_in_rate,
        a.loanx_id,
        b.SECURITY_ID,
        b.CUSIP_ID,
        a.business_date,
        a.lead_manager AS lead_manager_1,
        b.lead_manager AS lead_manager_2,
        a.deal_sponsor
    FROM loanx_id_cte a
    JOIN loanx_id_cte b
        ON a.business_date = b.business_date
        AND a.loanx_id = b.loanx_id
        AND a.lead_manager <> b.lead_manager
        AND COALESCE(a.lead_manager,'') <> ''
        AND COALESCE(b.lead_manager,'') <> ''
),

security_result AS (
    SELECT 
        a.weighted_average_all_in_rate,
        a.loanx_id,
        b.SECURITY_ID,
        b.CUSIP_ID,
        a.business_date,
        a.lead_manager AS lead_manager_1,
        b.lead_manager AS lead_manager_2,
        a.deal_sponsor
    FROM security_id_cte a
    JOIN security_id_cte b
        ON a.business_date = b.business_date
        AND a.SECURITY_ID = b.SECURITY_ID
        AND a.lead_manager <> b.lead_manager
        AND COALESCE(a.lead_manager,'') <> ''
        AND COALESCE(b.lead_manager,'') <> ''
),

cusip_result AS (
    SELECT 
        a.weighted_average_all_in_rate,
        a.loanx_id,
        b.SECURITY_ID,
        b.CUSIP_ID,
        a.business_date,
        a.lead_manager AS lead_manager_1,
        b.lead_manager AS lead_manager_2,
        a.deal_sponsor
    FROM cusip_id_cte a
    JOIN cusip_id_cte b
        ON a.business_date = b.business_date
        AND a.CUSIP_ID = b.CUSIP_ID
        AND a.lead_manager <> b.lead_manager
        AND COALESCE(a.lead_manager,'') <> ''
        AND COALESCE(b.lead_manager,'') <> ''
)

SELECT * FROM loanx_result
UNION ALL
SELECT * FROM security_result
UNION ALL
SELECT * FROM cusip_result;
