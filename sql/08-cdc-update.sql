DO $demo$
BEGIN
    UPDATE tienda.productos SET precio = 125.00, stock = 9
    WHERE producto_id = 9001 AND nombre = 'Producto demo CDC' AND precio = 100.00;
    IF NOT FOUND THEN RAISE EXCEPTION 'Ejecutá primero 07-cdc-insert.sql; no se modificaron filas'; END IF;
END
$demo$;
