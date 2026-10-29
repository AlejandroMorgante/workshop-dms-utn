DO $demo$
BEGIN
    DELETE FROM tienda.productos
    WHERE producto_id = 9001 AND nombre = 'Producto demo CDC' AND precio = 125.00;
    IF NOT FOUND THEN RAISE EXCEPTION 'Ejecutá primero 08-cdc-update.sql; no se eliminaron filas'; END IF;
END
$demo$;
