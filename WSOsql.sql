WITH loanx_id AS (
  SELECT 
    weighted_average_all_in_rate,
   -- ALADDIN_ID,
    loanx_id,
    SECURITY_ID,
    CUSIP_ID,
    business_date,
    lead_manager,
    deal_sponsor
  FROM PROD_STAGING.PUBLIC.WSO_DAILY_SECURITYMASTER_ENRICHMENT
  where (coalesce(loanx_id ,'') <> '') --or (coalesce(SECURITY_ID ,'') <> '') or (coalesce(CUSIP_ID ,'') <> ''))
)
SELECT 
  a.weighted_average_all_in_rate,
 -- a.ALADDIN_ID,
  a.loanx_id,
   b.SECURITY_ID,
    b.CUSIP_ID,
  a.business_date,
  a.lead_manager as lead_manager_1,
  b.lead_manager as lead_manager_2,
  a.deal_sponsor
FROM same_name a
JOIN same_name b 
  ON a.business_date = b.business_date 
  AND (a.loanx_id = b.loanx_id) --or (a.SECURITY_ID = b.SECURITY_ID) or (a.CUSIP_ID = b.CUSIP_ID))
  AND a.lead_manager <> b.lead_manager
  and (coalesce(a.lead_manager,'') <> '' and coalesce(b.lead_manager,'') <> '')
  ), SECURITY_ID as
  (
  SELECT 
    weighted_average_all_in_rate,
   -- ALADDIN_ID,
    loanx_id,
    SECURITY_ID,
    CUSIP_ID,
    business_date,
    lead_manager,
    deal_sponsor
  FROM PROD_STAGING.PUBLIC.WSO_DAILY_SECURITYMASTER_ENRICHMENT
  where (coalesce(SECURITY_ID ,'') <> '') --or (coalesce(SECURITY_ID ,'') <> '') or (coalesce(CUSIP_ID ,'') <> ''))
)
SELECT 
  a.weighted_average_all_in_rate,
 -- a.ALADDIN_ID,
  a.loanx_id,
   b.SECURITY_ID,
    b.CUSIP_ID,
  a.business_date,
  a.lead_manager as lead_manager_1,
  b.lead_manager as lead_manager_2,
  a.deal_sponsor
FROM same_name a
JOIN same_name b 
  ON a.business_date = b.business_date 
  AND (a.SECURITY_ID = b.SECURITY_ID) --or (a.SECURITY_ID = b.SECURITY_ID) or (a.CUSIP_ID = b.CUSIP_ID))
  AND a.lead_manager <> b.lead_manager
  and (coalesce(a.lead_manager,'') <> '' and coalesce(b.lead_manager,'') <> '')
  ), CUSIP_ID as
  (
  SELECT 
    weighted_average_all_in_rate,
   -- ALADDIN_ID,
    loanx_id,
    SECURITY_ID,
    CUSIP_ID,
    business_date,
    lead_manager,
    deal_sponsor
  FROM PROD_STAGING.PUBLIC.WSO_DAILY_SECURITYMASTER_ENRICHMENT
  where (coalesce(CUSIP_ID ,'') <> '') --or (coalesce(SECURITY_ID ,'') <> '') or (coalesce(CUSIP_ID ,'') <> ''))
)
SELECT 
  a.weighted_average_all_in_rate,
 -- a.ALADDIN_ID,
  a.loanx_id,
   b.SECURITY_ID,
    b.CUSIP_ID,
  a.business_date,
  a.lead_manager as lead_manager_1,
  b.lead_manager as lead_manager_2,
  a.deal_sponsor
FROM same_name a
JOIN same_name b 
  ON a.business_date = b.business_date 
  AND (a.CUSIP_ID = b.CUSIP_ID) --or (a.SECURITY_ID = b.SECURITY_ID) or (a.CUSIP_ID = b.CUSIP_ID))
  AND a.lead_manager <> b.lead_manager
  and (coalesce(a.lead_manager,'') <> '' and coalesce(b.lead_manager,'') <> '')
  )
  select * from loanx_id
  union all
  select * from SECURITY_ID
  union all
  select * from CUSIP_ID;
