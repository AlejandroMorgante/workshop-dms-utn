-- Synthetic data only. Rerunning adds missing IDs; it does not overwrite changes.
DO $seed$
BEGIN
    INSERT INTO tienda.clientes (cliente_id, nombre, ciudad, creado_en) VALUES
        (1, 'Ada', 'Buenos Aires', '2026-10-01 10:00:00+00'),
        (2, 'Bruno', 'Córdoba', '2026-10-01 11:00:00+00'),
        (3, 'Cata', 'Rosario', '2026-10-02 12:00:00+00'),
        (4, 'Dante', 'Mendoza', '2026-10-02 13:00:00+00'),
        (5, 'Emma', 'La Plata', '2026-10-03 14:00:00+00')
    ON CONFLICT (cliente_id) DO NOTHING;

    INSERT INTO tienda.productos (producto_id, nombre, categoria, precio, stock) VALUES
        (1, 'Teclado', 'periféricos', 45000.00, 30),
        (2, 'Mouse', 'periféricos', 18000.00, 50),
        (3, 'Monitor', 'pantallas', 220000.00, 12),
        (4, 'Webcam', 'video', 65000.00, 20),
        (5, 'Auriculares', 'audio', 38000.00, 25),
        (6, 'Micrófono', 'audio', 85000.00, 10)
    ON CONFLICT (producto_id) DO NOTHING;

    INSERT INTO tienda.pedidos (pedido_id, cliente_id, estado, creado_en, actualizado_en) VALUES
        (1001, 1, 'pagado', '2026-10-20 10:00:00+00', '2026-10-20 10:00:00+00'),
        (1002, 2, 'enviado', '2026-10-20 14:30:00+00', '2026-10-21 09:00:00+00'),
        (1003, 3, 'pendiente', '2026-10-21 09:15:00+00', '2026-10-21 09:15:00+00'),
        (1004, 1, 'pagado', '2026-10-21 16:00:00+00', '2026-10-21 16:00:00+00'),
        (1005, 4, 'cancelado', '2026-10-22 11:00:00+00', '2026-10-22 12:00:00+00'),
        (1006, 5, 'pendiente', '2026-10-22 15:45:00+00', '2026-10-22 15:45:00+00'),
        (1007, 2, 'pagado', '2026-10-23 10:30:00+00', '2026-10-23 10:30:00+00'),
        (1008, 3, 'pendiente', '2026-10-23 17:00:00+00', '2026-10-23 17:00:00+00')
    ON CONFLICT (pedido_id) DO NOTHING;

    INSERT INTO tienda.items_pedido (item_id, pedido_id, producto_id, cantidad, precio_unitario) VALUES
        (1, 1001, 1, 1, 45000.00), (2, 1001, 2, 1, 18000.00),
        (3, 1002, 3, 1, 220000.00), (4, 1002, 4, 1, 65000.00),
        (5, 1003, 5, 2, 38000.00), (6, 1004, 6, 1, 85000.00),
        (7, 1005, 1, 1, 45000.00), (8, 1006, 2, 2, 18000.00),
        (9, 1007, 3, 1, 220000.00), (10, 1007, 5, 1, 38000.00),
        (11, 1008, 4, 1, 65000.00), (12, 1008, 6, 1, 85000.00)
    ON CONFLICT (item_id) DO NOTHING;
END
$seed$;
