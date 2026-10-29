-- Ejecutar una vez, después de que la carga inicial de la task CDC llegue a 100%.
INSERT INTO tienda.productos (producto_id, nombre, categoria, precio, stock)
VALUES (9001, 'Producto demo CDC', 'Workshop', 100.00, 10);
