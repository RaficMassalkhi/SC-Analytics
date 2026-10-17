-- KPI 25: Capacity Utilization %
-- Current inventory units ÷ capacity_units

SELECT
    ri.warehouse_id,
    SUM(ri.ending_inventory) AS current_inventory_units,
    w.capacity_units,
    ROUND(100.0 * SUM(ri.ending_inventory) / w.capacity_units, 2) AS capacity_utilization_pct

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

JOIN warehouses w
    ON ri.warehouse_id = w.warehouse_id

GROUP BY
    ri.warehouse_id,
    w.capacity_units

ORDER BY
    ri.warehouse_id;


-- KPI 26: Capacity Risk
-- Current inventory + relevant inbound pipeline compared with capacity
-- Inbound pipeline is based on outstanding quantities on open/partial POs

SELECT
    ri.warehouse_id,
    SUM(ri.ending_inventory) AS current_inventory_units,
    COALESCE(inbound.inbound_units, 0) AS inbound_pipeline_units,
    SUM(ri.ending_inventory) + COALESCE(inbound.inbound_units, 0) AS projected_inventory_units,
    w.capacity_units

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

JOIN warehouses w
    ON ri.warehouse_id = w.warehouse_id

LEFT JOIN (
    SELECT
        po.warehouse_id,
        SUM(pol.quantity_ordered - pol.quantity_received) AS inbound_units

    FROM purchase_orders po

    JOIN purchase_order_lines pol
        ON po.purchase_order_id = pol.purchase_order_id

    WHERE po.status IN ('open', 'partial')
      AND pol.quantity_ordered > pol.quantity_received

    GROUP BY
        po.warehouse_id
) inbound
    ON ri.warehouse_id = inbound.warehouse_id

GROUP BY
    ri.warehouse_id,
    w.capacity_units,
    inbound.inbound_units

ORDER BY
    ri.warehouse_id;

-- KPI 30: Projected Inventory 
-- Current stock + outstanding inbound quantity

SELECT
    ri.warehouse_id,
    SUM(ri.ending_inventory) AS current_inventory_units,
    COALESCE(inbound.inbound_pipeline_units, 0) AS inbound_pipeline_units,
    SUM(ri.ending_inventory) + COALESCE(inbound.inbound_pipeline_units, 0) AS projected_inventory_units

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

LEFT JOIN (
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
) inbound
    ON ri.warehouse_id = inbound.warehouse_id

GROUP BY
    ri.warehouse_id,
    inbound.inbound_pipeline_units

ORDER BY
    ri.warehouse_id;

-- KPI 31: Projected Capacity Utilization 
-- (Current stock + inbound pipeline) ÷ capacity

SELECT
    ri.warehouse_id,
    SUM(ri.ending_inventory) AS current_inventory_units,
    COALESCE(inbound.inbound_units, 0) AS inbound_pipeline_units,
    SUM(ri.ending_inventory) + COALESCE(inbound.inbound_units, 0) AS projected_inventory_units,
    w.capacity_units,
    ROUND(100.0 * (SUM(ri.ending_inventory) + COALESCE(inbound.inbound_units, 0)) / w.capacity_units, 2) 
    AS projected_capacity_utilization

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

JOIN warehouses w
    ON ri.warehouse_id = w.warehouse_id

LEFT JOIN (
    SELECT
        po.warehouse_id,
        SUM(pol.quantity_ordered - pol.quantity_received) AS inbound_units

    FROM purchase_orders po

    JOIN purchase_order_lines pol
        ON po.purchase_order_id = pol.purchase_order_id

    WHERE po.status IN ('open', 'partial')
      AND pol.quantity_ordered > pol.quantity_received

    GROUP BY
        po.warehouse_id
) inbound
    ON ri.warehouse_id = inbound.warehouse_id

GROUP BY
    ri.warehouse_id,
    w.capacity_units,
    inbound.inbound_units

ORDER BY
    ri.warehouse_id;