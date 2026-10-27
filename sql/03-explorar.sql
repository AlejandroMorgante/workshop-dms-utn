SELECT p.pedido_id,
       c.nombre AS cliente,
       c.ciudad,
       p.estado,
       to_char(p.creado_en AT TIME ZONE 'UTC', 'YYYY-MM-DD') AS fecha_utc,
       sum(i.cantidad * i.precio_unitario)::numeric(12, 2) AS total
FROM tienda.pedidos AS p
JOIN tienda.clientes AS c ON c.cliente_id = p.cliente_id
JOIN tienda.items_pedido AS i ON i.pedido_id = p.pedido_id
GROUP BY p.pedido_id, c.nombre, c.ciudad, p.estado, p.creado_en
ORDER BY p.pedido_id;
