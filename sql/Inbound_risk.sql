-- KPI 1: Outstanding PO Value 
-- Sum(quantity_ordered - quantity_received) x unit_cost
-- The master unit cost is being used for ALL calculations (products table)

SELECT
    po.supplier_id,
    po.warehouse_id,
    pol.product_id,
    SUM(pol.quantity_ordered - pol.quantity_received) AS outstanding_units,
    SUM((pol.quantity_ordered - pol.quantity_received) * p.unit_cost) AS outstanding_po_value

FROM purchase_orders po

JOIN purchase_order_lines pol
    ON po.purchase_order_id = pol.purchase_order_id

JOIN products p
    ON pol.product_id = p.product_id

WHERE po.status IN ('open', 'partial')

GROUP BY
    po.supplier_id,
    po.warehouse_id,
    pol.product_id

HAVING
    SUM(pol.quantity_ordered - pol.quantity_received) > 0;


-- KPI 29: Inbound Pipeline Units
-- Outstanding ordered quantity assigned to destination warehouse

SELECT
    po.warehouse_id,
    SUM(pol.quantity_ordered - pol.quantity_received) AS inbound_pipeline_units

FROM purchase_orders po

JOIN purchase_order_lines pol
    ON po.purchase_order_id = pol.purchase_order_id

WHERE po.status IN ('open', 'partial')

    AND pol.quantity_ordered > pol.quantity_received

GROUP BY
    po.warehouse_id

ORDER BY
    po.warehouse_id;

-- KPI 32: Supply-at-Risk SKUs
-- Flag low/stockout inventory combined with poor supplier service or late inbound

SELECT
    inventory.product_id,
    inventory.supplier_id,
    inventory.low_inventory_warehouses,
    supplier.supplier_otd_pct,
    COALESCE(late_inbound.late_inbound_units, 0) AS late_inbound_units

FROM (
    SELECT
        ri.product_id,
        p.supplier_id,
        COUNT(CASE
                WHEN ri.ending_inventory <= p.reorder_point
                THEN 1
            END) AS low_inventory_warehouses

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
        ri.product_id,
        p.supplier_id
) inventory

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
    ON inventory.supplier_id = supplier.supplier_id

LEFT JOIN (
    SELECT
        pol.product_id,
        SUM(pol.quantity_ordered - pol.quantity_received) AS late_inbound_units

    FROM purchase_orders po

    JOIN purchase_order_lines pol
        ON po.purchase_order_id = pol.purchase_order_id

    WHERE po.status IN ('open', 'partial')
        AND pol.quantity_ordered > pol.quantity_received
        AND po.expected_at < '2026-01-01'

    GROUP BY
        pol.product_id
) late_inbound
    ON inventory.product_id = late_inbound.product_id

WHERE
    inventory.low_inventory_warehouses > 0

    AND (supplier.supplier_otd_pct < 90
        OR COALESCE(late_inbound.late_inbound_units, 0) > 0)

ORDER BY
    inventory.product_id;

-- KPI 35: Late PO Exposure 
-- Outstanding value on POs past expected_at

SELECT
    po.warehouse_id,
    ROUND(SUM((pol.quantity_ordered - pol.quantity_received) * p.unit_cost), 2) AS late_po_exposure_value

FROM purchase_orders po

JOIN purchase_order_lines pol
    ON po.purchase_order_id = pol.purchase_order_id

JOIN products p
    ON pol.product_id = p.product_id

WHERE po.status IN ('open', 'partial')
    AND pol.quantity_ordered > pol.quantity_received
    AND po.expected_at < '2026-01-01'

GROUP BY
    po.warehouse_id

ORDER BY
    po.warehouse_id;

-- KPI 36: Stockout Exposure
-- Stockout or below-ROP positions with insufficient/no inbound pipeline

SELECT
    inventory.warehouse_id,
    SUM(CASE
            WHEN inventory.ending_inventory <= inventory.reorder_point
            THEN MAX(inventory.reorder_point
                - inventory.ending_inventory
                - COALESCE(inbound.inbound_units, 0) , 0)
            ELSE 0
        END) AS uncovered_shortage_units,
    ROUND(SUM(CASE
                WHEN inventory.ending_inventory <= inventory.reorder_point
                THEN MAX(inventory.reorder_point
                    - inventory.ending_inventory
                    - COALESCE(inbound.inbound_units, 0), 0) * inventory.unit_cost
                ELSE 0
            END), 2) AS stockout_exposure_value

FROM (
    SELECT
        ri.product_id,
        ri.warehouse_id,
        ri.ending_inventory,
        p.reorder_point,
        p.unit_cost

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
) inventory

LEFT JOIN (
    SELECT
        po.warehouse_id,
        pol.product_id,
        SUM(pol.quantity_ordered - pol.quantity_received) AS inbound_units

    FROM purchase_orders po

    JOIN purchase_order_lines pol
        ON po.purchase_order_id = pol.purchase_order_id

    WHERE po.status IN ('open', 'partial')
        AND pol.quantity_ordered > pol.quantity_received

    GROUP BY
        po.warehouse_id,
        pol.product_id
) inbound
    ON inventory.warehouse_id = inbound.warehouse_id
    AND inventory.product_id = inbound.product_id

GROUP BY
    inventory.warehouse_id

ORDER BY
    inventory.warehouse_id;