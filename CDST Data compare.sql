WITH OLD_RESULT AS (
    ---- paste OLD query here
),

NEW_RESULT AS (
    ---- paste NEW query here
),

COMPARISON AS (
    SELECT
        COALESCE(o.business_date, n.business_date) AS business_date,
        COALESCE(o.aladdin_id, n.aladdin_id) AS aladdin_id,

        o.coupon_rate AS old_coupon_rate,
        n.coupon_rate AS new_coupon_rate,

        /* Difference with tolerance */
        ABS(NVL(o.coupon_rate,0) - NVL(n.coupon_rate,0)) AS coupon_diff

    FROM OLD_RESULT o
    FULL OUTER JOIN NEW_RESULT n
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
      old_coupon_rate IS NULL
   OR new_coupon_rate IS NULL
   OR coupon_diff > 0.0001   -- tolerance
ORDER BY aladdin_id;
