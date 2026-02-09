WITH normalized_data AS (

    SELECT 
        weighted_average_all_in_rate,
        loanx_id AS instrument_id,
        'LOANX_ID' AS id_type,
        SECURITY_ID,
        CUSIP_ID,
        business_date,
        lead_manager,
        deal_sponsor
    FROM PROD_STAGING.PUBLIC.WSO_DAILY_SECURITYMASTER_ENRICHMENT
    WHERE COALESCE(loanx_id,'') <> ''

    UNION ALL

    SELECT 
        weighted_average_all_in_rate,
        SECURITY_ID AS instrument_id,
        'SECURITY_ID' AS id_type,
        SECURITY_ID,
        CUSIP_ID,
        business_date,
        lead_manager,
        deal_sponsor
    FROM PROD_STAGING.PUBLIC.WSO_DAILY_SECURITYMASTER_ENRICHMENT
    WHERE COALESCE(SECURITY_ID,'') <> ''

    UNION ALL

    SELECT 
        weighted_average_all_in_rate,
        CUSIP_ID AS instrument_id,
        'CUSIP_ID' AS id_type,
        SECURITY_ID,
        CUSIP_ID,
        business_date,
        lead_manager,
        deal_sponsor
    FROM PROD_STAGING.PUBLIC.WSO_DAILY_SECURITYMASTER_ENRICHMENT
    WHERE COALESCE(CUSIP_ID,'') <> ''
)

SELECT
    a.weighted_average_all_in_rate,
    a.instrument_id,
    a.id_type,
    a.SECURITY_ID,
    a.CUSIP_ID,
    a.business_date,
    a.lead_manager AS lead_manager_1,
    b.lead_manager AS lead_manager_2,
    a.deal_sponsor
FROM normalized_data a
JOIN normalized_data b
    ON a.business_date = b.business_date
    AND a.instrument_id = b.instrument_id
    AND a.id_type = b.id_type
    AND a.lead_manager <> b.lead_manager
    AND COALESCE(a.lead_manager,'') <> ''
    AND COALESCE(b.lead_manager,'') <> '';
