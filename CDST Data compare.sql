WITH COMPARISON AS (
    SELECT
        COALESCE(o.business_date, n.business_date) AS business_date,
        COALESCE(o.aladdin_id, n.aladdin_id) AS aladdin_id,

        /* Keep both versions clearly named */
        o.LEAD_MANAGER AS old_lead_manager,
        n.LEAD_MANAGER AS new_lead_manager,
        o.DEAL_SPONSOR AS old_deal_sponsor,
        n.DEAL_SPONSOR AS new_deal_sponsor,

        o.coupon_rate AS old_coupon_rate,
        n.coupon_rate AS new_coupon_rate,

        /* Proper NULL-safe difference */
        ABS(COALESCE(o.coupon_rate,0) - COALESCE(n.coupon_rate,0)) AS coupon_diff

    FROM SANDBOX_01.VAITHI_DEV.STAGE_DIM_ASSET_DATA_COMPARE_BEFORE o
    FULL OUTER JOIN SANDBOX_01.VAITHI_DEV.STAGE_DIM_ASSET_DATA_COMPARE_AFTER n
        ON o.business_date = n.business_date
        AND o.aladdin_id = n.aladdin_id
)

SELECT
    business_date,
    aladdin_id,
    old_coupon_rate,
    new_coupon_rate,
    coupon_diff
FROM COMPARISON
WHERE
      business_date = '2026-02-11'
  AND (
        old_coupon_rate IS NULL
        OR new_coupon_rate IS NULL
        OR coupon_diff > 0
      )
ORDER BY business_date DESC, aladdin_id;
