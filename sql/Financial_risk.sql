-- KPI 33: Supplier Dependency Risk
-- Combine spend/volume concentration with supplier performance
-- Risk is measured by top-spend suppliers + OTD below 90%.

SELECT
    spend.supplier_id,
    ROUND(spend.supplier_spend, 2) AS supplier_spend,
    ROUND(100.0 * spend.supplier_spend / totals.total_spend, 2) AS spend_share_pct,
    supplier.supplier_otd_pct,
    CASE
        WHEN spend.supplier_spend >= concentration.concentration_threshold
             AND supplier.supplier_otd_pct < 90
        THEN 'High Risk'
        ELSE 'Normal'
    END AS dependency_risk

FROM (
    SELECT
        po.supplier_id,
        SUM(pol.quantity_ordered * p.unit_cost) AS supplier_spend

    FROM purchase_orders po

    JOIN purchase_order_lines pol
        ON po.purchase_order_id = pol.purchase_order_id

    JOIN products p
        ON pol.product_id = p.product_id

    GROUP BY
        po.supplier_id
) spend

CROSS JOIN (
    SELECT
        SUM(pol.quantity_ordered * p.unit_cost) AS total_spend

    FROM purchase_orders po

    JOIN purchase_order_lines pol
        ON po.purchase_order_id = pol.purchase_order_id

    JOIN products p
        ON pol.product_id = p.product_id
) totals

JOIN (
    SELECT
        supplier_id,
        ROUND(100.0 * COUNT(CASE
                    WHEN received_at <= expected_at
                    THEN 1
                END) / COUNT(*), 2) AS supplier_otd_pct

    FROM purchase_orders

    WHERE NULLIF(TRIM(received_at), '') IS NOT NULL

    GROUP BY
        supplier_id
) supplier
    ON spend.supplier_id = supplier.supplier_id

CROSS JOIN (
    SELECT
        MIN(supplier_spend) AS concentration_threshold

    FROM (
        SELECT
            po.supplier_id,
            SUM(pol.quantity_ordered * p.unit_cost) AS supplier_spend

        FROM purchase_orders po

        JOIN purchase_order_lines pol
            ON po.purchase_order_id = pol.purchase_order_id

        JOIN products p
            ON pol.product_id = p.product_id

        GROUP BY
            po.supplier_id

        ORDER BY
            supplier_spend DESC

        LIMIT 25
    )
) concentration

ORDER BY
    spend.supplier_spend DESC;

-- KPI 34: Inventory-at-Risk Value
-- Value of slow, non-moving, excess or otherwise flagged stock

SELECT
    risk.warehouse_id,
    ROUND(SUM(CASE
                WHEN risk.non_moving_flag = 1
                    OR risk.slow_moving_flag = 1
                    OR risk.excess_flag = 1
                    OR risk.low_inventory_flag = 1
                THEN MAX(risk.ending_inventory, 0) * risk.unit_cost
                ELSE 0
            END), 2) AS inventory_at_risk_value

FROM (
    SELECT
        ri.product_id,
        ri.warehouse_id,
        ri.ending_inventory,
        p.unit_cost,
        p.reorder_point,
        CASE
            WHEN ri.ending_inventory > 0
                AND (ri.last_outbound IS NULL
                    OR julianday((
                        SELECT MAX(movement_at)
                         FROM inventory_movements))
                     - julianday(ri.last_outbound) > 90)
            THEN 1
            ELSE 0
        END AS non_moving_flag,
        CASE
            WHEN ri.ending_inventory > 0
                AND ri.outbound_90_days BETWEEN 1 AND 25
            THEN 1
            ELSE 0
        END AS slow_moving_flag,
        CASE
            WHEN ri.ending_inventory > (ri.total_outbound_units / 1096.0 * 30)
            THEN 1
            ELSE 0
        END AS excess_flag,
        CASE
            WHEN ri.ending_inventory <= p.reorder_point
            THEN 1
            ELSE 0
        END AS low_inventory_flag

    FROM (
        SELECT
            iob.product_id,
            iob.warehouse_id,
            iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory,
            SUM(CASE
                    WHEN im.movement_type = 'sale'
                        AND julianday((
                            SELECT MAX(movement_at)
                             FROM inventory_movements))
                         - julianday(im.movement_at) <= 90
                    THEN -im.quantity_change
                    ELSE 0
                END) AS outbound_90_days,
            SUM(CASE
                    WHEN im.movement_type = 'sale'
                    THEN -im.quantity_change
                    ELSE 0
                END) AS total_outbound_units,
            MAX(CASE
                    WHEN im.movement_type = 'sale'
                    THEN im.movement_at
                END) AS last_outbound

        FROM inventory_opening_balances iob

        LEFT JOIN inventory_movements im
            ON iob.product_id = im.product_id
            AND iob.warehouse_id = im.warehouse_id

        GROUP BY
            iob.product_id,
            iob.warehouse_id,
            iob.opening_units
    ) ri

    JOIN products p
        ON ri.product_id = p.product_id
) risk

GROUP BY
    risk.warehouse_id

ORDER BY
    risk.warehouse_id;


-- KPI 37: Working Capital Proxy
-- Total current inventory value

SELECT
    ri.warehouse_id,
    ROUND(SUM(MAX(ri.ending_inventory,0) * p.unit_cost), 2) AS working_capital_proxy

FROM (
    SELECT
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units + COALESCE(SUM(im.quantity_change), 0) AS ending_inventory

    FROM inventory_opening_balances iob

    LEFT JOIN inventory_movements im
        ON iob.product_id = im.product_id
        AND iob.warehouse_id = im.warehouse_id

    GROUP BY
        iob.product_id,
        iob.warehouse_id,
        iob.opening_units
) ri

JOIN products p
    ON ri.product_id = p.product_id

GROUP BY
    ri.warehouse_id

ORDER BY
    ri.warehouse_id;